import AppKit
import Preferences
import StatusKit
import XCTest

@testable import WindowKit

final class TestClock: StatusClock, @unchecked Sendable {
  var now: TimeInterval = 0
}

/// Holds the wakeups that a status center asks for, so a test fires them by hand.
@MainActor
final class TestScheduler {
  private(set) var actions: [@MainActor () -> Void] = []

  func schedule(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void)
    -> @MainActor ()
    -> Void
  {
    actions.append(action)
    return {}
  }

  func fireLast() {
    actions.last?()
  }
}

@MainActor
final class AppletLog {
  var made: [FakeApplet] = []
}

/// One window over an isolated defaults suite, a manual clock, and fake applets. The first applet
/// is the first pane's.
@MainActor
final class WindowFixture {
  let suite = "uniterm-window-test-\(UUID().uuidString)"
  let defaults: UserDefaults
  let store: SettingsStore
  let clock = TestClock()
  let scheduler = TestScheduler()
  let center: StatusCenter
  let log: AppletLog
  let controller: MainWindowController

  init(storedPosition: String? = nil) throws {
    let defaults = UserDefaults(suiteName: suite)!
    if let storedPosition {
      defaults.set(storedPosition, forKey: "statusBarPosition")
    }

    let store = SettingsStore(defaults: defaults)
    let clock = clock
    let scheduler = scheduler
    let center = StatusCenter(clock: clock, scheduler: scheduler.schedule)
    let log = AppletLog()

    self.defaults = defaults
    self.store = store
    self.center = center
    self.log = log

    controller = try MainWindowController(
      appearance: AppearanceController(store: store), settings: store, statusCenter: center
    ) { _ in
      let applet = FakeApplet()
      log.made.append(applet)
      return applet
    }

    controller.window?.contentView?.layoutSubtreeIfNeeded()
  }

  func cleanUp() {
    defaults.removePersistentDomain(forName: suite)
  }

  var bar: StatusBarView { controller.contentController.statusBar }
  var paneArea: PaneAreaView { controller.paneArea }
  var chrome: NSView { controller.contentController.view }

  func layout() {
    chrome.layoutSubtreeIfNeeded()
  }

  /// The text of the message area.
  var messageText: String? {
    bar.segments.first { $0.id == .message }?.text
  }
}

/// Polls until a condition holds. A store reports a change on a later turn of the main actor.
@MainActor
func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) async -> Bool {
  let deadline = Date().addingTimeInterval(timeout)

  while Date() < deadline {
    if condition() { return true }

    try? await Task.sleep(for: .milliseconds(20))
  }

  return condition()
}

/// Runs `defaults` as a separate process, as a user's `defaults write` does.
func runDefaults(_ arguments: [String]) throws -> String {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
  process.arguments = arguments

  let pipe = Pipe()
  process.standardOutput = pipe
  try process.run()

  let output = pipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  XCTAssertEqual(process.terminationStatus, 0, "defaults \(arguments) failed")

  return String(decoding: output, as: UTF8.self)
}

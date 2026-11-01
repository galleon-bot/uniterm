import AppKit
import AppletKit
import Preferences
import XCTest

@testable import WindowKit

/// Quit asks under the same rule as a window close, across every window. The window set owns the
/// rule, so it is tested here and not through the app delegate.
@MainActor
final class QuitGuardTests: XCTestCase {
  private let suite = "uniterm-quit-test-\(UUID().uuidString)"
  private var windows: WindowSet?
  private var asked: [CloseConfirmation] = []
  private var answer = false
  private let log = AppletLog()
  private var made: [FakeApplet] { log.made }

  override func setUp() async throws {
    asked = []
    answer = false
    log.made = []
  }

  override func tearDown() async throws {
    for controller in windows?.controllers ?? [] {
      controller.window?.close()
    }

    windows = nil
    UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
  }

  private func makeWindows() -> WindowSet {
    let store = SettingsStore(defaults: UserDefaults(suiteName: suite)!)
    let appearance = AppearanceController(store: store)
    let log = log

    let set = WindowSet(
      confirmer: { [unowned self] request, _ in
        asked.append(request)
        return answer
      },
      makeController: { [unowned self] identifier in
        try MainWindowController(
          appearance: appearance, settings: store, identifier: identifier
        ) { _ in
          let applet = FakeApplet()
          applet.title = "Fake \(log.made.count)"
          log.made.append(applet)
          return applet
        }
      })

    windows = set
    return set
  }

  /// Catches a quit that forgets a window, or a hidden pane. Window one is idle. Window two has a
  /// visible pane running make and a hidden pane running vim. Quit lists both, and nothing from
  /// window one.
  func testQuitCountsEveryWindowsRunningTabsHiddenOnesIncluded() async throws {
    let set = makeWindows()
    try set.open()
    let second = try set.open()
    second.openPane(.terminalShell, axis: .row)
    made[1].isRunningSomething = true
    made[1].labels = ["make test"]
    made[2].isRunningSomething = true
    made[2].labels = ["vim"]
    second.closePane(nil)

    XCTAssertEqual(set.runningTabLabels, ["make test", "vim"])
    XCTAssertEqual(second.paneIDs.count, 1)

    answer = false
    let proceed = await set.shouldQuit()

    XCTAssertFalse(proceed)
    XCTAssertEqual(asked.count, 1)
    XCTAssertEqual(asked[0].labels.sorted(), ["make test", "vim"])
    XCTAssertEqual(asked[0].confirmTitle, "Quit")

    answer = true
    let confirmed = await set.shouldQuit()

    XCTAssertTrue(confirmed)
  }

  /// Catches a quit that asks although nothing is running anywhere.
  func testQuitWithNothingRunningAsksNothing() async throws {
    let set = makeWindows()
    try set.open()

    let proceed = await set.shouldQuit()

    XCTAssertTrue(proceed)
    XCTAssertTrue(asked.isEmpty)
  }

  /// Catches a quit that leaves hidden processes behind. Hanging up ends the hidden panes of every
  /// window and leaves the visible ones alone.
  func testQuitHangsUpHiddenPanesInEveryWindow() throws {
    let set = makeWindows()
    let first = try set.open()
    let second = try set.open()
    first.openPane(.terminalShell, axis: .row)
    second.openPane(.terminalShell, axis: .row)
    first.closePane(nil)
    second.closePane(nil)
    XCTAssertEqual(made.map(\.closed), [false, false, false, false])

    set.hangUpHiddenPanes()

    XCTAssertEqual(made.map(\.closed), [false, false, true, true])
    XCTAssertTrue(first.ledger.hidden.isEmpty)
    XCTAssertTrue(second.ledger.hidden.isEmpty)
  }
}

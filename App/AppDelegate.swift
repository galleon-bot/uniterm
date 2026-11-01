import AppKit
import OSLog
import Preferences
import SettingsKit
import StatusKit
import TerminalApplet
import TerminalSurface
import WindowKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let logger = Logger(subsystem: "dev.uniterm.app", category: "app")
  private let settings = SettingsStore(defaults: AppDelegate.makeDefaults())
  private var appearance: AppearanceController?
  private var appearanceToken: UUID?
  private var paletteSync: TerminalPaletteSync?
  private var terminalEngine: GhosttyTerminalEngine?
  private var windowSet: WindowSet?
  private var settingsWindowController: SettingsWindowController?

  /// UI tests set `UNITERM_DEFAULTS_PATH` to a plist path inside the test runner's container, so
  /// they never touch the developer's real preferences. A write to that file from the sandboxed
  /// runner reaches the running app the way `defaults write` would.
  private static func makeDefaults() -> UserDefaults {
    guard let path = ProcessInfo.processInfo.environment["UNITERM_DEFAULTS_PATH"],
      let defaults = UserDefaults(suiteName: path)
    else {
      return .standard
    }

    return defaults
  }

  /// UI tests set `UNITERM_TERMINAL_DIR` so the generated terminal config stays out of the
  /// developer's Application Support folder. Only debug builds honor it, since a release build has
  /// no test to serve.
  private static func terminalConfigDirectory() throws -> URL {
    #if DEBUG
      if let path = ProcessInfo.processInfo.environment["UNITERM_TERMINAL_DIR"] {
        return URL(fileURLWithPath: path, isDirectory: true)
      }
    #endif

    return try TerminalConfigStore.defaultDirectory()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    logger.info("libghostty \(TerminalSurfaceInfo.libraryVersion, privacy: .public)")

    let appearance = AppearanceController(store: settings)
    self.appearance = appearance

    let engine: GhosttyTerminalEngine
    do {
      engine = try GhosttyTerminalEngine(
        configStore: TerminalConfigStore(directory: try Self.terminalConfigDirectory()),
        resourcesDirectory: nil, palette: appearance.palette)
    } catch {
      logger.error("the terminal engine did not start: \(String(describing: error))")

      let alert = NSAlert()
      alert.alertStyle = .critical
      alert.messageText = "uniterm could not start its terminal engine"
      alert.informativeText = "\(error)"
      alert.runModal()
      NSApp.terminate(nil)
      return
    }

    terminalEngine = engine

    NSApp.mainMenu = MainMenu.make(target: self)

    let settings = settings
    let windows = WindowSet { identifier in
      try MainWindowController(appearance: appearance, settings: settings, identifier: identifier) {
        choice in
        switch choice {
        case .terminalShell:
          return TerminalApplet(engine: engine)

        case .terminalProgram(let command):
          return try TerminalApplet(engine: engine, program: command)
        }
      }
    }
    windowSet = windows

    let controller: MainWindowController
    do {
      controller = try windows.open()
    } catch {
      logger.error("the first pane did not start: \(String(describing: error))")
      NSApp.terminate(nil)
      return
    }

    let sync = TerminalPaletteSync(engine: engine) { [weak self] error in
      self?.paletteDidNotApply(error)
    }
    paletteSync = sync
    appearanceToken = appearance.addObserver { palette in
      sync.apply(palette)
    }

    NSApp.activate()

    postDebugError(to: controller)
  }

  /// UI tests set `UNITERM_DEBUG_POST_ERROR` to get an error on the status bar without relying on
  /// a feature that may change. Only debug builds honor it.
  private func postDebugError(to controller: MainWindowController) {
    #if DEBUG
      if let text = ProcessInfo.processInfo.environment["UNITERM_DEBUG_POST_ERROR"] {
        controller.statusCenter.post(level: .error, source: .uniterm, text: text)
      }
    #endif
  }

  func applicationWillTerminate(_ notification: Notification) {
    terminalEngine?.removeConfigFile()
  }

  /// Closing the last window leaves the app running, as on macOS generally. Cmd-N or a click on
  /// the Dock icon opens a new window, and Cmd-Q quits.
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  /// A click on the Dock icon opens a window when none is open. The Settings window does not
  /// count. With a window open, minimized or not, AppKit's own handling brings it back.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    !openWindow(onlyIfNone: true)
  }

  private func paletteDidNotApply(_ error: any Error) {
    logger.error("the terminal palette did not update: \(String(describing: error))")
    windowSet?.post(
      level: .error, source: .uniterm, text: "The terminal colors did not update: \(error)")
  }

  @objc func newWindow(_ sender: Any?) {
    openWindow()
  }

  /// Says whether a window opened. With `onlyIfNone`, an open window means nothing opens.
  @discardableResult
  private func openWindow(onlyIfNone: Bool = false) -> Bool {
    guard let windowSet else { return false }

    do {
      if onlyIfNone { return try windowSet.openIfNone() }

      try windowSet.open()
      return true
    } catch {
      logger.error("the window did not open: \(String(describing: error))")

      if let active = windowSet.activeController {
        active.statusCenter.post(
          level: .error, source: .uniterm, text: "The window did not open: \(error)")
        return false
      }

      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = "uniterm could not open a window"
      alert.informativeText = "\(error)"
      alert.runModal()
      return false
    }
  }

  @objc func showSettings(_ sender: Any?) {
    let controller = settingsWindowController ?? SettingsWindowController(store: settings)
    settingsWindowController = controller
    controller.present()
  }
}

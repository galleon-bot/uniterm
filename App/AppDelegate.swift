import AppKit
import OSLog
import Preferences
import SettingsKit
import TerminalSurface
import WindowKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let logger = Logger(subsystem: "dev.uniterm.app", category: "app")
  private let settings = SettingsStore(defaults: AppDelegate.makeDefaults())
  private var appearance: AppearanceController?
  private var mainWindowController: MainWindowController?
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

  func applicationDidFinishLaunching(_ notification: Notification) {
    logger.info("libghostty \(TerminalSurfaceInfo.libraryVersion, privacy: .public)")

    let appearance = AppearanceController(store: settings)
    self.appearance = appearance

    NSApp.mainMenu = MainMenu.make(target: self)

    let controller = MainWindowController(appearance: appearance)
    mainWindowController = controller
    controller.showWindow(nil)
    NSApp.activate()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  @objc func showSettings(_ sender: Any?) {
    let controller = settingsWindowController ?? SettingsWindowController(store: settings)
    settingsWindowController = controller
    controller.present()
  }
}

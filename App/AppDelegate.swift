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

    let controller: MainWindowController
    do {
      controller = try MainWindowController(appearance: appearance, settings: settings) { choice in
        switch choice {
        case .terminalShell:
          return TerminalApplet(engine: engine)

        case .terminalProgram(let command):
          return try TerminalApplet(engine: engine, program: command)
        }
      }
    } catch {
      logger.error("the first pane did not start: \(String(describing: error))")
      NSApp.terminate(nil)
      return
    }

    mainWindowController = controller

    let sync = TerminalPaletteSync(engine: engine) { [weak self] error in
      self?.paletteDidNotApply(error)
    }
    paletteSync = sync
    appearanceToken = appearance.addObserver { palette in
      sync.apply(palette)
    }

    controller.showWindow(nil)
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

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  private func paletteDidNotApply(_ error: any Error) {
    logger.error("the terminal palette did not update: \(String(describing: error))")
    mainWindowController?.statusCenter.post(
      level: .error, source: .uniterm, text: "The terminal colors did not update: \(error)")
  }

  @objc func showSettings(_ sender: Any?) {
    let controller = settingsWindowController ?? SettingsWindowController(store: settings)
    settingsWindowController = controller
    controller.present()
  }
}

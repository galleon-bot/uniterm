import XCTest

/// The base class of every UI test. It launches the app in an isolated environment.
///
/// The app reads a throwaway plist for its preferences and writes its terminal config to a scratch
/// folder, so no test touches the developer's settings.
///
/// The shell reads a fixture folder through `ZDOTDIR` and never the developer's dotfiles. Those may
/// prompt for an ssh passphrase or run anything else. Ghostty's zsh integration restores `ZDOTDIR`
/// for the startup files, so the integration stays on. The production app still starts the user's
/// real login shell.
@MainActor
class UnitermUITestCase: XCTestCase {
  private(set) var scratch = ""
  private var launched: [XCUIApplication] = []

  override func setUpWithError() throws {
    continueAfterFailure = false
    scratch = NSTemporaryDirectory() + "uniterm-ui-\(UUID().uuidString)"

    try FileManager.default.createDirectory(
      atPath: scratch + "-shell", withIntermediateDirectories: true)
    try Data().write(to: URL(fileURLWithPath: scratch + "-shell/.zshrc"))
  }

  /// A leftover instance would be logged at the next launch, so every test ends its app.
  override func tearDownWithError() throws {
    for app in launched where app.state != .notRunning {
      app.terminate()
    }

    launched = []
    try? FileManager.default.removeItem(atPath: scratch + "-shell")
    try? FileManager.default.removeItem(atPath: scratch + "-terminal")
  }

  func launchApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["UNITERM_DEFAULTS_PATH"] = scratch
    app.launchEnvironment["UNITERM_TERMINAL_DIR"] = scratch + "-terminal"
    app.launchEnvironment["SHELL"] = "/bin/zsh"
    app.launchEnvironment["ZDOTDIR"] = scratch + "-shell"
    app.launchEnvironment["SSH_AUTH_SOCK"] = ""
    app.launch()
    app.activate()
    launched.append(app)
    return app
  }
}

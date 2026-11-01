import XCTest

/// Drives the launched app with a real shell in its pane. Each test proves a contract that only the
/// window server and AppKit's key routing can show.
///
/// The tests read marker output that the typed command alone cannot produce. A command such as
/// `echo "T:$TERM:"` shows `T:$TERM:` as typed and `T:xterm-ghostty:` as output.
///
/// The tests type no apostrophes. When a UI test typed one, the logged key event had the Control
/// flag set (flags 262144) and the terminal sent CSI 39;5u. A double quote arrived with the Shift
/// flag only (131072). That points at the synthetic event, but it is an observation and not a
/// proof. The key translation is covered in the package tests.
@MainActor
final class TerminalUITests: UnitermUITestCase {
  /// Catches a pane that does not take keyboard focus, a shell that starts with the wrong TERM, and
  /// bundled terminfo that infocmp cannot find.
  func testShellTakesInputAndReportsGhosttyTerm() {
    let app = launchApp()
    let terminal = waitForTerminal(in: app)

    app.typeText("echo \"T:$TERM:\"; infocmp xterm-ghostty >/dev/null && echo \"I:$((6*7)):\"\n")

    XCTAssertTrue(
      waitFor(terminal, timeout: 40) {
        $0.contains("T:xterm-ghostty:") && $0.contains("I:42:")
      }, "TERM or the bundled terminfo is wrong. Screen: \(terminal.value as? String ?? "")")
  }

  /// Catches a window resize that never reaches the shell. The grid changes, and `stty size` in
  /// the shell reports a different size afterwards.
  func testShellSeesTheWindowSize() {
    let app = launchApp()
    let window = app.windows["main-window"]
    let terminal = waitForTerminal(in: app)

    app.typeText("echo \"A:$(stty size | tr \" \" x):\"\n")
    XCTAssertTrue(
      waitFor(terminal, timeout: 40) {
        $0.range(of: #"A:\d+x\d+:"#, options: .regularExpression) != nil
      }, "no size reported. Screen: \(terminal.value as? String ?? "")")
    let first = firstMatch(#"A:(\d+x\d+):"#, in: terminal.value as? String ?? "")

    let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(
      CGVector(dx: -2, dy: -2))
    corner.press(forDuration: 0.1, thenDragTo: corner.withOffset(CGVector(dx: -300, dy: -150)))

    app.typeText("echo \"B:$(stty size | tr \" \" x):\"\n")
    XCTAssertTrue(
      waitFor(terminal, timeout: 20) {
        $0.range(of: #"B:\d+x\d+:"#, options: .regularExpression) != nil
      })
    let second = firstMatch(#"B:(\d+x\d+):"#, in: terminal.value as? String ?? "")
    print("TERMINAL SCREEN AFTER RESIZE>>>\n\(terminal.value as? String ?? "")\n<<<")

    XCTAssertNotNil(first)
    XCTAssertNotNil(second)
    XCTAssertNotEqual(first, second, "the shell kept its old size after the window shrank")
  }

  /// Catches Ghostty's built-in bindings catching keys before uniterm. With the terminal focused,
  /// Cmd-T, Cmd-D, and Cmd-Z reach uniterm's menu. Each answers with a status message.
  func testCommandKeysReachUnitermWhileTheTerminalIsFocused() {
    let app = launchApp()
    let window = app.windows["main-window"]
    _ = waitForTerminal(in: app)
    let message = window.staticTexts["status-message"]

    app.typeKey("t", modifierFlags: .command)
    XCTAssertTrue(waitFor(message, timeout: 5) { $0.contains("Tabs are not available yet.") })

    app.typeKey("d", modifierFlags: .command)
    XCTAssertTrue(waitFor(message, timeout: 5) { $0.contains("Splits are not available yet.") })

    app.typeKey("z", modifierFlags: .command)
    XCTAssertTrue(waitFor(message, timeout: 5) { $0.contains("no closed pane to undo") })
  }

  /// Cmd-W closes the pane, and with one pane the window closes and the app ends.
  func testCommandWClosesThePaneAndTheWindow() {
    let app = launchApp()
    _ = waitForTerminal(in: app)

    app.typeKey("w", modifierFlags: .command)

    XCTAssertTrue(app.wait(for: .notRunning, timeout: 15))
  }

  /// Cmd-Q reaches uniterm while the terminal is focused.
  func testCommandQQuits() {
    let app = launchApp()
    _ = waitForTerminal(in: app)

    app.typeKey("q", modifierFlags: .command)

    XCTAssertTrue(app.wait(for: .notRunning, timeout: 15))
  }

  /// Catches a shell exit that leaves an empty pane open.
  func testShellExitClosesThePane() {
    let app = launchApp()
    let terminal = waitForTerminal(in: app)

    app.typeText("echo \"R:$((40+2)):\"\n")
    XCTAssertTrue(waitFor(terminal, timeout: 40) { $0.contains("R:42:") })

    app.typeText("exit\n")

    XCTAssertTrue(app.wait(for: .notRunning, timeout: 20))
  }

  /// Catches a clear-screen menu item that does not reach the terminal. The marker leaves the
  /// screen after Cmd-K.
  func testClearScreenClearsTheTerminal() {
    let app = launchApp()
    let terminal = waitForTerminal(in: app)

    app.typeText("echo \"C:$((40+2)):\"\n")
    XCTAssertTrue(waitFor(terminal, timeout: 40) { $0.contains("C:42:") })

    app.typeKey("k", modifierFlags: .command)

    XCTAssertTrue(waitFor(terminal, timeout: 10) { !$0.contains("C:42:") })
  }

  // MARK: Helpers

  private func waitForTerminal(in app: XCUIApplication) -> XCUIElement {
    let terminal = app.windows["main-window"].textViews["terminal"]
    XCTAssertTrue(terminal.waitForExistence(timeout: 15))

    // Keys typed before the shell reads its terminal can be lost. The fixture's zsh prompt ends in
    // "% ", so wait for it.
    XCTAssertTrue(
      waitFor(terminal, timeout: 40) { $0.contains("% ") }, "the shell never showed a prompt")
    return terminal
  }

  private func waitFor(
    _ element: XCUIElement, timeout: TimeInterval, _ condition: @escaping (String) -> Bool
  ) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
      if let value = element.value as? String, condition(value) {
        return true
      }

      Thread.sleep(forTimeInterval: 0.25)
    }

    return false
  }

  private func firstMatch(_ pattern: String, in text: String) -> String? {
    guard let expression = try? NSRegularExpression(pattern: pattern),
      let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
      match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text)
    else { return nil }

    return String(text[range])
  }
}

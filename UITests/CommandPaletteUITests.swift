import XCTest

/// Drives the command palette in the launched app. Each test proves a contract that only AppKit's
/// key routing, the real menu, and the field editor can show.
///
/// The App Shortcuts remaps use the `-NSUserKeyEquivalents` launch argument. It lands in the app's
/// argument domain, which AppKit reads for menu items the way it reads a remap saved in System
/// Settings.
@MainActor
final class CommandPaletteUITests: UnitermUITestCase {
  private func palette(in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)["command-palette"]
  }

  private func field(in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)["command-palette-field"]
  }

  private func tab(_ index: Int, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)["tab-\(index)"]
  }

  private func showPalette(
    in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
  ) {
    app.typeKey("p", modifierFlags: [.command, .shift])
    XCTAssertTrue(
      palette(in: app).waitForExistence(timeout: 5), "the palette never showed", file: file,
      line: line)
  }

  /// Catches a Cmd-Shift-P that a focused terminal takes, a palette that does not hide on the
  /// same key, and an Escape that leaves the keyboard in the palette. Keys typed after the hide
  /// must reach the terminal.
  func testTheHotkeyTogglesThePaletteAndEscapeReturnsTheKeyboardToTheTerminal() {
    let app = launchApp()
    let terminal = waitForTerminal(in: app)

    showPalette(in: app)

    app.typeKey("p", modifierFlags: [.command, .shift])
    XCTAssertTrue(waitUntilGone(palette(in: app)), "the toggle did not hide the palette")

    showPalette(in: app)
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(waitUntilGone(palette(in: app)), "Escape did not hide the palette")

    app.typeText("echo back-in-terminal\n")
    XCTAssertTrue(
      waitFor(terminal, timeout: 20) { $0.contains("back-in-terminal") },
      "the terminal did not get the keyboard back")
  }

  /// Catches a palette command that does not run on Enter.
  func testTypingFiltersAndEnterRunsTheCommand() {
    let app = launchApp()
    _ = waitForTerminal(in: app)

    showPalette(in: app)
    app.typeText("split right")
    app.typeKey(.return, modifierFlags: [])

    XCTAssertTrue(waitUntilGone(palette(in: app)))
    XCTAssertTrue(
      launcher(in: mainWindow(in: app)).waitForExistence(timeout: 5),
      "Split Right did not open a pane")
  }

  /// Catches Cmd-W that closes the pane, and so the window, while the field has focus.
  func testCommandWInTheFieldDismissesAndClosesNothing() {
    let app = launchApp()
    _ = waitForTerminal(in: app)

    showPalette(in: app)
    app.typeKey("w", modifierFlags: .command)

    XCTAssertTrue(waitUntilGone(palette(in: app)))
    XCTAssertTrue(mainWindow(in: app).exists, "Cmd-W closed the window")
    XCTAssertTrue(mainWindow(in: app).textViews["terminal"].exists)
  }

  /// Catches Cmd-V and Cmd-Z that reach the pane or the window and not the field.
  func testPasteAndUndoEditTheField() {
    let app = launchApp()
    _ = waitForTerminal(in: app)

    showPalette(in: app)
    app.typeText("ab")
    app.typeKey("a", modifierFlags: .command)
    app.typeKey("c", modifierFlags: .command)
    app.typeKey(.rightArrow, modifierFlags: [])
    app.typeKey("v", modifierFlags: .command)

    XCTAssertTrue(
      waitFor(field(in: app), timeout: 5) { $0 == "abab" }, "Cmd-V did not paste into the field")

    app.typeKey("z", modifierFlags: .command)

    XCTAssertTrue(
      waitFor(field(in: app), timeout: 5) { $0 == "ab" },
      "Cmd-Z did not undo the field's edit, value: \(String(describing: field(in: app).value))")
    XCTAssertTrue(palette(in: app).exists)
    XCTAssertTrue(mainWindow(in: app).textViews["terminal"].exists)
  }

  /// Catches a binding that runs while the palette holds the keyboard, or runs on the field. Cmd-T
  /// hides the palette and then opens the tab in the terminal.
  func testCommandTAfterDismissOpensATabInThePriorPane() {
    let app = launchApp()
    _ = waitForTerminal(in: app)

    showPalette(in: app)
    app.typeKey("t", modifierFlags: .command)

    XCTAssertTrue(waitUntilGone(palette(in: app)))
    XCTAssertTrue(tab(1, in: app).waitForExistence(timeout: 10), "Cmd-T did not open a tab")
  }

  /// Catches File > Close that takes another path than Cmd-W. With two tabs it closes the
  /// selected one. With the palette up it only dismisses it, as Cmd-W does.
  func testTheCloseMenuItemRunsTheCommandCommandWRuns() {
    let app = launchApp()
    _ = waitForTerminal(in: app)

    app.typeKey("t", modifierFlags: .command)
    XCTAssertTrue(tab(1, in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(
      waitFor(mainWindow(in: app).textViews["terminal"], timeout: 40) { $0.contains("% ") })

    showPalette(in: app)
    app.menuBars.menuItems["Close Tab"].click()

    XCTAssertTrue(waitUntilGone(palette(in: app)))
    XCTAssertTrue(tab(1, in: app).exists, "the menu item closed a tab with the palette up")

    app.menuBars.menuItems["Close Tab"].click()
    XCTAssertTrue(waitUntilGone(tab(1, in: app), timeout: 15), "File > Close did not close the tab")
  }

  /// Catches a remap that loses to the default binding of another item. Cmd-T is New Tab, and the
  /// remapped palette item must win even with the terminal focused.
  func testARemapOntoAnotherBindingWins() {
    let app = launchApp(arguments: ["-NSUserKeyEquivalents", #"{"Show Command Palette"="@t";}"#])
    _ = waitForTerminal(in: app)

    app.typeKey("t", modifierFlags: .command)

    XCTAssertTrue(palette(in: app).waitForExistence(timeout: 5), "the remapped key did not win")
    XCTAssertFalse(tab(1, in: app).exists, "New Tab ran instead")
  }

  /// Catches a remap onto a Control chord that the terminal would take as input.
  func testARemapOntoAControlChordReachesUnitermBeforeTheTerminal() {
    let app = launchApp(arguments: ["-NSUserKeyEquivalents", #"{"Show Command Palette"="^g";}"#])
    _ = waitForTerminal(in: app)

    app.typeKey("g", modifierFlags: .control)

    XCTAssertTrue(palette(in: app).waitForExistence(timeout: 5), "the terminal took the key")
  }
}

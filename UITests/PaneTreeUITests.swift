import XCTest

/// Drives the pane tree in the launched app. Each test proves a contract that only AppKit's views,
/// the window server, and real key routing can show.
///
/// Every shell comes from the shared launch helper, so none reads the developer's dotfiles.
@MainActor
final class PaneTreeUITests: UnitermUITestCase {
  /// Catches a split that does not nest and place panes: Cmd-D puts a second pane to the right of
  /// the first, and Cmd-Shift-D puts a third one below the second. Each pane runs its own shell.
  func testSplitsNestAndEachPaneRunsAShell() {
    let app = launchApp()
    let window = app.windows["main-window"]
    _ = waitForTerminal(in: app)

    openPane(in: app, keys: "d", modifiers: .command)
    XCTAssertTrue(waitForPaneCount(2, in: window))
    openPane(in: app, keys: "d", modifiers: [.command, .shift])
    XCTAssertTrue(waitForPaneCount(3, in: window))

    let panes = panesInReadingOrder(in: window)
    let one = panes[0].frame
    let two = panes[1].frame
    let three = panes[2].frame

    XCTAssertGreaterThanOrEqual(two.minX, one.maxX, "the second pane is not right of the first")
    XCTAssertGreaterThanOrEqual(three.minY, two.maxY - 1, "the third pane is not below the second")
    XCTAssertEqual(three.minX, two.minX, accuracy: 2)
    XCTAssertEqual(window.textViews.matching(identifier: "terminal").count, 3)

    for pane in panes {
      XCTAssertTrue(
        waitFor(pane.textViews["terminal"], timeout: 40) { $0.contains("% ") },
        "a pane never showed a prompt")
    }
  }

  /// Catches focus that does not follow the keyboard: the new pane is focused, Cmd-Option-Left
  /// and Cmd-Option-Right move between panes, Cmd-[ and Cmd-] walk the order, and typed text
  /// reaches only the focused pane's shell.
  func testFocusMovesWithTheKeyboardAndInputReachesOnlyTheFocusedPane() {
    let app = launchApp()
    let window = app.windows["main-window"]
    _ = waitForTerminal(in: app)

    openPane(in: app, keys: "d", modifiers: .command)
    let one = window.groups["pane-1"]
    let two = window.groups["pane-2"]
    XCTAssertTrue(two.waitForExistence(timeout: 20))
    XCTAssertTrue(waitFor(two.textViews["terminal"], timeout: 40) { $0.contains("% ") })
    XCTAssertEqual(two.value as? String, "focused")
    XCTAssertEqual(one.value as? String, "unfocused")

    app.typeKey(.leftArrow, modifierFlags: [.command, .option])
    XCTAssertTrue(waitForValue("focused", of: one))
    XCTAssertTrue(waitForValue("unfocused", of: two))

    app.typeText("echo \"L:$((6*7)):\"\n")
    XCTAssertTrue(waitFor(one.textViews["terminal"], timeout: 20) { $0.contains("L:42:") })
    XCTAssertFalse((two.textViews["terminal"].value as? String ?? "").contains("L:42:"))

    app.typeKey(.rightArrow, modifierFlags: [.command, .option])
    XCTAssertTrue(waitForValue("focused", of: two))

    app.typeKey("[", modifierFlags: .command)
    XCTAssertTrue(waitForValue("focused", of: one))

    app.typeKey("]", modifierFlags: .command)
    XCTAssertTrue(waitForValue("focused", of: two))
  }

  /// Catches the vertical focus keys not reaching uniterm while a terminal is focused. After
  /// Cmd-Shift-D the new pane is below the first. Cmd-Option-Up moves focus to the first pane and
  /// Cmd-Option-Down moves it back. The horizontal keys and Cmd-[ and Cmd-] are covered above.
  func testVerticalFocusKeysReachUnitermFromAFocusedTerminal() {
    let app = launchApp()
    let window = app.windows["main-window"]
    _ = waitForTerminal(in: app)

    openPane(in: app, keys: "d", modifiers: [.command, .shift])
    let one = window.groups["pane-1"]
    let two = window.groups["pane-2"]
    XCTAssertTrue(two.waitForExistence(timeout: 20))
    XCTAssertTrue(waitFor(two.textViews["terminal"], timeout: 40) { $0.contains("% ") })
    XCTAssertTrue(waitForValue("focused", of: two))

    app.typeKey(.upArrow, modifierFlags: [.command, .option])
    XCTAssertTrue(waitForValue("focused", of: one))

    app.typeKey(.downArrow, modifierFlags: [.command, .option])
    XCTAssertTrue(waitForValue("focused", of: two))
  }

  /// Catches a click that does not move the focus mark: clicking the first pane's terminal
  /// focuses it.
  func testClickingAPaneFocusesIt() {
    let app = launchApp()
    let window = app.windows["main-window"]
    _ = waitForTerminal(in: app)

    openPane(in: app, keys: "d", modifiers: .command)
    let one = window.groups["pane-1"]
    XCTAssertTrue(window.groups["pane-2"].waitForExistence(timeout: 20))
    XCTAssertTrue(waitForValue("unfocused", of: one))

    one.textViews["terminal"].click()

    XCTAssertTrue(waitForValue("focused", of: one))
  }

  /// Catches a divider that cannot be dragged: dragging it 100 points right grows pane 1 by about
  /// 100 and shrinks pane 2 by the same amount.
  func testDraggingADividerResizesThePanesOnBothSides() {
    let app = launchApp()
    let window = app.windows["main-window"]
    _ = waitForTerminal(in: app)

    openPane(in: app, keys: "d", modifiers: .command)
    XCTAssertTrue(window.groups["pane-2"].waitForExistence(timeout: 20))

    let divider = app.descendants(matching: .any)["divider-1-2"]
    XCTAssertTrue(divider.waitForExistence(timeout: 5))

    let before1 = window.groups["pane-1"].frame.width
    let before2 = window.groups["pane-2"].frame.width

    let center = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    center.press(forDuration: 0.2, thenDragTo: center.withOffset(CGVector(dx: 100, dy: 0)))

    XCTAssertEqual(window.groups["pane-1"].frame.width - before1, 100, accuracy: 8)
    XCTAssertEqual(before2 - window.groups["pane-2"].frame.width, 100, accuracy: 8)
  }

  /// Catches a close that leaves a hole or kills the window: Cmd-W closes the focused pane, the
  /// window stays, and the first pane takes the whole width again.
  func testClosingAPaneGivesItsSpaceToTheNeighbor() {
    let app = launchApp()
    let window = app.windows["main-window"]
    _ = waitForTerminal(in: app)
    let whole = window.groups["pane-1"].frame.width

    openPane(in: app, keys: "d", modifiers: .command)
    XCTAssertTrue(window.groups["pane-2"].waitForExistence(timeout: 20))
    XCTAssertLessThan(window.groups["pane-1"].frame.width, whole - 100)

    app.typeKey("w", modifierFlags: .command)

    let gone = NSPredicate(format: "exists == false")
    XCTAssertEqual(
      XCTWaiter().wait(
        for: [XCTNSPredicateExpectation(predicate: gone, object: window.groups["pane-2"])],
        timeout: 15), .completed)
    XCTAssertTrue(window.exists)
    XCTAssertEqual(window.groups["pane-1"].frame.width, whole, accuracy: 2)
  }

  /// Catches a window that can shrink past its panes. With three panes in a row the minimum is
  /// 3 * 200 + 2 * 5 = 610 wide. A drag that asks for far less stops there, and no pane is
  /// narrower than 200.
  func testShrinkingTheWindowStopsAtTheTreesMinimum() {
    let app = launchApp()
    let window = app.windows["main-window"]
    _ = waitForTerminal(in: app)

    openPane(in: app, keys: "d", modifiers: .command)
    XCTAssertTrue(waitForPaneCount(2, in: window))
    openPane(in: app, keys: "d", modifiers: .command)
    XCTAssertTrue(waitForPaneCount(3, in: window))

    let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(
      CGVector(dx: -2, dy: -2))
    corner.press(forDuration: 0.1, thenDragTo: corner.withOffset(CGVector(dx: -700, dy: 0)))

    XCTAssertEqual(window.frame.width, 610, accuracy: 2)
    for pane in panesInReadingOrder(in: window) {
      XCTAssertGreaterThanOrEqual(pane.frame.width, 199, "a pane is narrower than its minimum")
    }
  }

  /// Catches a split that is refused silently: with three panes in a row, a fourth does not fit.
  /// The status bar says so, and the sheet never opens.
  func testASplitThatDoesNotFitIsRefusedWithAMessage() {
    let app = launchApp()
    let window = app.windows["main-window"]
    _ = waitForTerminal(in: app)

    openPane(in: app, keys: "d", modifiers: .command)
    XCTAssertTrue(waitForPaneCount(2, in: window))
    openPane(in: app, keys: "d", modifiers: .command)
    XCTAssertTrue(waitForPaneCount(3, in: window))

    app.typeKey("d", modifierFlags: .command)

    let message = window.staticTexts["status-message"]
    XCTAssertTrue(waitFor(message, timeout: 5) { $0.contains("not enough room") })
    XCTAssertFalse(window.sheets.firstMatch.exists)
    XCTAssertEqual(paneGroups(in: window).count, 3)
  }

  /// Catches a picker that offers no program mode: the sheet lists the terminal in shell mode and
  /// in program mode, the command field appears only for program mode, and Open stays disabled
  /// until a command is typed. Opening it adds a pane that runs the program.
  func testThePickerOffersProgramModeWithACommand() {
    let app = launchApp()
    let window = app.windows["main-window"]
    _ = waitForTerminal(in: app)

    app.typeKey("d", modifierFlags: .command)
    let sheet = window.sheets.firstMatch
    XCTAssertTrue(sheet.waitForExistence(timeout: 5))
    XCTAssertFalse(sheet.textFields["pane-command"].exists)

    let popup = sheet.popUpButtons["pane-applet"]
    popup.click()
    XCTAssertTrue(app.menuItems["Terminal"].waitForExistence(timeout: 5))
    app.menuItems["Terminal running a program"].click()

    let field = sheet.textFields["pane-command"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    XCTAssertFalse(sheet.buttons["Open"].isEnabled)

    field.click()
    field.typeText("sh -c \"echo PR:42:; cat\"")
    XCTAssertTrue(sheet.buttons["Open"].isEnabled)

    sheet.buttons["Open"].click()

    let pane = window.groups["pane-2"]
    XCTAssertTrue(pane.waitForExistence(timeout: 20), "program mode opened no pane")
    XCTAssertTrue(waitFor(pane.textViews["terminal"], timeout: 40) { $0.contains("PR:42:") })
  }

  /// Catches a Cancel that still opens a pane.
  func testCancellingThePickerOpensNoPane() {
    let app = launchApp()
    let window = app.windows["main-window"]
    _ = waitForTerminal(in: app)

    app.typeKey("d", modifierFlags: .command)
    XCTAssertTrue(window.sheets.firstMatch.waitForExistence(timeout: 5))

    app.typeKey(.escape, modifierFlags: [])

    XCTAssertTrue(waitForNoSheet(in: window))
    XCTAssertFalse(window.groups["pane-2"].exists)
  }

  // MARK: Helpers

  /// Presses a split key, then accepts the picker's default, a terminal in shell mode.
  private func openPane(
    in app: XCUIApplication, keys: String, modifiers: XCUIElement.KeyModifierFlags
  ) {
    let window = app.windows["main-window"]

    app.typeKey(keys, modifierFlags: modifiers)
    XCTAssertTrue(window.sheets.firstMatch.waitForExistence(timeout: 5), "the picker never opened")

    app.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(waitForNoSheet(in: window))
  }

  private func paneGroups(in window: XCUIElement) -> XCUIElementQuery {
    window.groups.matching(NSPredicate(format: "identifier BEGINSWITH 'pane-'"))
  }

  /// Waits for the number of pane groups, never for an ID. The allocator numbers splits too, so
  /// the third pane of a window is pane 4. Only the first split is certain to make pane 2.
  private func waitForPaneCount(_ count: Int, in window: XCUIElement, timeout: TimeInterval = 20)
    -> Bool
  {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
      if paneGroups(in: window).count == count { return true }

      Thread.sleep(forTimeInterval: 0.25)
    }

    return false
  }

  /// The pane groups from left to right, and top to bottom where they share a left edge.
  private func panesInReadingOrder(in window: XCUIElement) -> [XCUIElement] {
    paneGroups(in: window).allElementsBoundByIndex.sorted {
      let a = $0.frame
      let b = $1.frame
      return (a.minX.rounded(), a.minY.rounded()) < (b.minX.rounded(), b.minY.rounded())
    }
  }

  private func waitForValue(_ expected: String, of element: XCUIElement) -> Bool {
    let predicate = NSPredicate(format: "value == %@", expected)
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    return XCTWaiter().wait(for: [expectation], timeout: 10) == .completed
  }
}

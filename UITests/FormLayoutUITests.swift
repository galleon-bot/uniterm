import XCTest

/// Checks the layout of the Settings window and the new-pane sheet in the running app, and attaches
/// a screenshot of each to the result bundle. Unit tests prove the frames in a bare window. These
/// prove them under the window server, in light and in dark.
@MainActor
final class FormLayoutUITests: UnitermUITestCase {
  private func attach(_ element: XCUIElement, named name: String) {
    let attachment = XCTAttachment(screenshot: element.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// Catches Settings controls that start at different x positions, labels that end at different x
  /// positions, and a control that touches the window edge.
  func testSettingsFormIsAlignedAndInsideItsWindowInLightAndDark() {
    let app = launchApp()
    XCTAssertTrue(app.windows["main-window"].waitForExistence(timeout: 10))

    app.typeKey(",", modifierFlags: .command)
    let settings = app.windows["settings-window"]
    XCTAssertTrue(settings.waitForExistence(timeout: 5))

    let appearance = settings.radioGroups["appearance-control"]
    let statusBar = settings.radioGroups["status-bar-position-control"]
    XCTAssertTrue(appearance.waitForExistence(timeout: 5))
    XCTAssertTrue(statusBar.exists)

    for (name, button) in [("light", "Light"), ("dark", "Dark")] {
      appearance.radioButtons[button].click()
      Thread.sleep(forTimeInterval: 0.5)

      let appearanceLabel = settings.staticTexts["Appearance:"]
      let statusLabel = settings.staticTexts["Status bar:"]
      XCTAssertEqual(appearance.frame.minX, statusBar.frame.minX, accuracy: 1, name)
      XCTAssertEqual(appearanceLabel.frame.maxX, statusLabel.frame.maxX, accuracy: 4, name)

      for control in [appearance, statusBar] {
        XCTAssertGreaterThanOrEqual(
          control.frame.minX, settings.frame.minX + 16, "\(name): too close to the leading edge")
        XCTAssertLessThanOrEqual(
          control.frame.maxX, settings.frame.maxX - 16, "\(name): too close to the trailing edge")
      }

      attach(settings, named: "settings-\(name)")
    }
  }

  /// Catches a sheet whose subtitle draws over the popup, in either mode, and a command field that
  /// does not make room for itself.
  func testNewPaneSheetDoesNotOverlapInEitherModeInLightAndDark() {
    let app = launchApp()
    let window = app.windows["main-window"]
    _ = waitForTerminal(in: app)

    for (name, button) in [("light", "Light"), ("dark", "Dark")] {
      app.typeKey(",", modifierFlags: .command)
      let settings = app.windows["settings-window"]
      XCTAssertTrue(settings.waitForExistence(timeout: 5))
      settings.radioGroups["appearance-control"].radioButtons[button].click()
      app.typeKey("w", modifierFlags: .command)
      XCTAssertTrue(waitUntilGone(settings, timeout: 5))

      app.typeKey("d", modifierFlags: .command)
      let sheet = window.sheets.firstMatch
      XCTAssertTrue(sheet.waitForExistence(timeout: 5))

      let subtitle = sheet.staticTexts["Choose what the pane runs."]
      let popup = sheet.popUpButtons["pane-applet"]
      XCTAssertTrue(subtitle.exists)
      XCTAssertFalse(subtitle.frame.intersects(popup.frame), "\(name) shell: subtitle overlaps")
      attach(sheet, named: "new-pane-shell-\(name)")

      let shellHeight = sheet.frame.height
      popup.click()
      XCTAssertTrue(app.menuItems["Terminal running a program"].waitForExistence(timeout: 5))
      app.menuItems["Terminal running a program"].click()

      let field = sheet.textFields["pane-command"]
      XCTAssertTrue(field.waitForExistence(timeout: 5))
      Thread.sleep(forTimeInterval: 0.5)
      XCTAssertFalse(subtitle.frame.intersects(popup.frame), "\(name) program: subtitle overlaps")
      XCTAssertFalse(popup.frame.intersects(field.frame), "\(name) program: popup overlaps field")
      XCTAssertFalse(
        field.frame.intersects(sheet.buttons["Open"].frame), "\(name): field overlaps buttons")
      XCTAssertGreaterThan(sheet.frame.height, shellHeight, "\(name): sheet did not grow")
      attach(sheet, named: "new-pane-program-\(name)")

      app.typeKey(.escape, modifierFlags: [])
      XCTAssertTrue(waitForNoSheet(in: window))
    }
  }
}

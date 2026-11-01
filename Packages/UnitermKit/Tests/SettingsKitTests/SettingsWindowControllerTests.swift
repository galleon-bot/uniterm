import AppKit
import Preferences
import XCTest

@testable import SettingsKit

@MainActor
final class SettingsWindowControllerTests: XCTestCase {
  /// Catches a Cmd-W that does nothing while Settings is the key window. The menu item has no
  /// target and the action is `closePane:`. The Settings controller answers it by closing its
  /// window. The test drives the responder chain from the window's content view, as AppKit does.
  func testClosePaneActionClosesTheSettingsWindow() throws {
    let store = SettingsStore(defaults: UserDefaults(suiteName: "uniterm-settings-\(UUID())")!)
    let controller = SettingsWindowController(store: store)
    let window = try XCTUnwrap(controller.window)
    window.orderFrontRegardless()
    XCTAssertTrue(window.isVisible)

    let handled = try XCTUnwrap(window.contentView).tryToPerform(
      NSSelectorFromString("closePane:"), with: nil)

    XCTAssertTrue(handled, "nothing in the Settings responder chain answers closePane:")
    XCTAssertFalse(window.isVisible)
  }
}

import AppKit
import Preferences
import XCTest

@testable import SettingsKit

@MainActor
final class SettingsWindowControllerTests: XCTestCase {
  private var suites: [String] = []

  override func tearDown() async throws {
    for suite in suites {
      UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    suites = []
  }

  private func makeStore(seed: [String: String] = [:]) -> SettingsStore {
    let suite = "uniterm-settings-\(UUID())"
    suites.append(suite)

    let defaults = UserDefaults(suiteName: suite)!
    for (key, value) in seed {
      defaults.set(value, forKey: key)
    }

    return SettingsStore(defaults: defaults)
  }

  private func control(_ identifier: String, in window: NSWindow) -> NSSegmentedControl? {
    func search(_ view: NSView) -> NSSegmentedControl? {
      if let control = view as? NSSegmentedControl, control.accessibilityIdentifier() == identifier
      {
        return control
      }

      for subview in view.subviews {
        if let found = search(subview) { return found }
      }

      return nil
    }

    return window.contentView.flatMap(search)
  }

  /// Catches a Cmd-W that does nothing while Settings is the key window. The menu item has no
  /// target and the action is `closePane:`. The Settings controller answers it by closing its
  /// window. The test drives the responder chain from the window's content view, as AppKit does.
  func testClosePaneActionClosesTheSettingsWindow() throws {
    let controller = SettingsWindowController(store: makeStore())
    let window = try XCTUnwrap(controller.window)
    window.orderFrontRegardless()
    XCTAssertTrue(window.isVisible)

    let handled = try XCTUnwrap(window.contentView).tryToPerform(
      NSSelectorFromString("closePane:"), with: nil)

    XCTAssertTrue(handled, "nothing in the Settings responder chain answers closePane:")
    XCTAssertFalse(window.isVisible)
  }

  /// Catches a Settings window with no status bar row, or a row that does not write the setting.
  func testStatusBarPositionRowWritesTheSetting() throws {
    let store = makeStore()
    let window = try XCTUnwrap(SettingsWindowController(store: store).window)
    let row = try XCTUnwrap(control("status-bar-position-control", in: window))

    XCTAssertEqual(row.segmentCount, 2)
    XCTAssertEqual(row.label(forSegment: 0), "Top")
    XCTAssertEqual(row.label(forSegment: 1), "Bottom")
    XCTAssertEqual(row.selectedSegment, 1, "the default is bottom")

    row.selectedSegment = 0
    _ = row.sendAction(row.action, to: row.target)
    XCTAssertEqual(store.value(of: .statusBarPosition), .top)

    row.selectedSegment = 1
    _ = row.sendAction(row.action, to: row.target)
    XCTAssertEqual(store.reading(of: .statusBarPosition), .valid(.bottom))
  }

  /// Catches a row that rewrites a value it does not understand.
  func testStatusBarPositionRowShowsTheDefaultForAnUnknownValueWithoutWritingIt() throws {
    let store = makeStore(seed: ["statusBarPosition": "sideways"])
    let window = try XCTUnwrap(SettingsWindowController(store: store).window)
    let row = try XCTUnwrap(control("status-bar-position-control", in: window))

    XCTAssertEqual(row.selectedSegment, 1)
    XCTAssertEqual(
      store.reading(of: .statusBarPosition), .invalid(raw: "sideways", fallback: .bottom))
  }

  /// Catches the appearance row going missing in the refactor that added the second row.
  func testAppearanceRowStillWritesTheSetting() throws {
    let store = makeStore()
    let window = try XCTUnwrap(SettingsWindowController(store: store).window)
    let row = try XCTUnwrap(control("appearance-control", in: window))

    XCTAssertEqual(row.segmentCount, 3)
    row.selectedSegment = 2
    _ = row.sendAction(row.action, to: row.target)

    XCTAssertEqual(store.value(of: .appearance), .dark)
  }
}

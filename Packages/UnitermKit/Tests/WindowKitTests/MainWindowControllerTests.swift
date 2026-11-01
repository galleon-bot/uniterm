import AppKit
import AppletKit
import Preferences
import StatusKit
import XCTest

@testable import WindowKit

@MainActor
private final class FakeApplet: Applet {
  let typeID = "fake"
  let view = NSView()
  var title = "Fake"
  var segments: [AppletSegment] = []
  var isRunningSomething = false
  weak var host: (any AppletHost)?
  var started = false
  var closed = false

  func start() { started = true }
  func close() { closed = true }
  func detach() {}
  func reattach() {}
  func focus() {}
  func describe() -> AppletDescription {
    AppletDescription(type: "fake", version: 1, payload: .null)
  }
}

@MainActor
final class MainWindowControllerTests: XCTestCase {
  private func makeController() -> (MainWindowController, FakeApplet) {
    let suite = "uniterm-window-test-\(UUID().uuidString)"
    let store = SettingsStore(defaults: UserDefaults(suiteName: suite)!)
    let appearance = AppearanceController(store: store)
    let applet = FakeApplet()
    let controller = MainWindowController(appearance: appearance) { applet }
    return (controller, applet)
  }

  /// Catches a message that loses its pane as source, so the bar cannot say which pane spoke.
  func testAppletMessagesPostWithThePaneAsSource() {
    let (controller, applet) = makeController()

    controller.applet(applet, post: .info, text: "build finished")

    let message = controller.statusCenter.history.last
    XCTAssertEqual(message?.text, "build finished")
    XCTAssertEqual(message?.level, .info)
    XCTAssertEqual(message?.source, .pane(id: 1, name: "Fake"))
  }

  /// Catches a shell that exits and leaves its window open, and a window that closes without
  /// closing its applet.
  func testAppletExitClosesTheWindowAndTheApplet() {
    let (controller, applet) = makeController()
    controller.window?.orderFrontRegardless()
    XCTAssertEqual(controller.window?.isVisible, true)

    controller.appletDidExit(applet)

    XCTAssertEqual(controller.window?.isVisible, false)
    XCTAssertTrue(applet.closed)
  }

  func testShowWindowStartsTheApplet() {
    let (controller, applet) = makeController()

    controller.showWindow(nil)
    defer { controller.window?.close() }

    XCTAssertTrue(applet.started)
  }

  /// Cmd-T, Cmd-D, and Cmd-Z are menu items answered by the window until their features exist.
  func testPlaceholderActionsAnswerWithAMessage() {
    let (controller, _) = makeController()

    controller.newTab(nil)
    controller.splitPane(nil)
    controller.undoClosePane(nil)

    XCTAssertEqual(controller.statusCenter.history.map(\.text).count, 3)
    XCTAssertTrue(controller.statusCenter.history.allSatisfy { $0.source == .uniterm })
  }
}

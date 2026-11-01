import AppKit
import AppletKit
import PaneModel
import Preferences
import StatusKit
import XCTest

@testable import WindowKit

@MainActor
final class MainWindowControllerTests: XCTestCase {
  /// The applets the factory handed out, in order. The first one is the window's first pane.
  private var made: [FakeApplet] = []
  private var choices: [AppletChoice] = []

  /// When set, the factory returns this applet instead of making one.
  private var reuse: FakeApplet?

  private func makeController() throws -> MainWindowController {
    let suite = "uniterm-window-test-\(UUID().uuidString)"
    let store = SettingsStore(defaults: UserDefaults(suiteName: suite)!)
    let appearance = AppearanceController(store: store)
    made = []
    choices = []
    reuse = nil

    let controller = try MainWindowController(appearance: appearance, settings: store) {
      [unowned self] choice in
      if case .terminalProgram = choice {
        throw AppletChoiceError("no programs in this test")
      }

      let applet = reuse ?? FakeApplet()
      reuse = nil
      made.append(applet)
      choices.append(choice)
      return applet
    }

    controller.window?.contentView?.layoutSubtreeIfNeeded()
    return controller
  }

  private func width(_ controller: MainWindowController, _ pane: UInt64) -> CGFloat {
    controller.paneArea.paneView(for: NodeID(rawValue: pane))?.frame.width ?? -1
  }

  // MARK: Single pane

  /// Catches a message that loses its pane as source, so the bar cannot say which pane spoke.
  func testAppletMessagesPostWithThePaneAsSource() throws {
    let controller = try makeController()

    controller.applet(made[0], post: .info, text: "build finished")

    let message = controller.statusCenter.history.last
    XCTAssertEqual(message?.text, "build finished")
    XCTAssertEqual(message?.level, .info)
    XCTAssertEqual(message?.source, .pane(id: 1, name: "Fake"))
  }

  /// Catches a shell that exits and leaves its window open, and a window that closes without
  /// closing its applet.
  func testLastAppletExitClosesTheWindowAndTheApplet() throws {
    let controller = try makeController()
    controller.window?.orderFrontRegardless()
    XCTAssertEqual(controller.window?.isVisible, true)

    controller.appletDidExit(made[0])

    XCTAssertEqual(controller.window?.isVisible, false)
    XCTAssertTrue(made[0].closed)
  }

  func testShowWindowStartsTheApplet() throws {
    let controller = try makeController()

    controller.showWindow(nil)
    defer { controller.window?.close() }

    XCTAssertTrue(made[0].started)
  }

  /// Cmd-T and Cmd-Z are menu items answered by the window until their features exist.
  func testPlaceholderActionsAnswerWithAMessage() throws {
    let controller = try makeController()

    controller.newTab(nil)
    controller.undoClosePane(nil)

    XCTAssertEqual(controller.statusCenter.history.count, 2)
    XCTAssertTrue(controller.statusCenter.history.allSatisfy { $0.source == .uniterm })
  }

  // MARK: Splitting

  /// Catches a split that does not reach the screen: a new pane with a started applet, focus on
  /// it, and the two panes sharing the width. The area is 960 wide with a 5 divider, so each pane
  /// is 477.5 before the frames round to whole points.
  func testSplitOpensAStartedPaneAndFocusesIt() throws {
    let controller = try makeController()
    XCTAssertEqual(controller.paneArea.bounds.width, 960, "the area has no size to split")

    let created = controller.openPane(.terminalShell, axis: .row)

    XCTAssertEqual(created, NodeID(rawValue: 2))
    XCTAssertEqual(controller.paneIDs, [NodeID(rawValue: 1), NodeID(rawValue: 2)])
    XCTAssertEqual(controller.focusedPane, NodeID(rawValue: 2))
    XCTAssertEqual(made.count, 2)
    XCTAssertTrue(made.allSatisfy(\.started))
    XCTAssertEqual(width(controller, 1), 477.5, accuracy: 1)
    XCTAssertEqual(width(controller, 2), 477.5, accuracy: 1)

    let first = controller.paneArea.paneView(for: NodeID(rawValue: 1))
    let second = controller.paneArea.paneView(for: NodeID(rawValue: 2))
    XCTAssertEqual(first?.frame.minX, 0)
    XCTAssertEqual(second?.frame.maxX, 960)
    XCTAssertEqual(controller.paneArea.dividers.count, 1)
  }

  /// Catches a focus mark that never moves, or that shows on a lone pane.
  func testOnlyTheFocusedPaneIsMarked() throws {
    let controller = try makeController()
    let first = controller.paneArea.paneView(for: NodeID(rawValue: 1))
    XCTAssertEqual(first?.showsFocusMarker, false)

    controller.openPane(.terminalShell, axis: .row)
    let second = controller.paneArea.paneView(for: NodeID(rawValue: 2))

    XCTAssertEqual(first?.showsFocusMarker, true)
    XCTAssertEqual(first?.accessibilityValue() as? String, "unfocused")
    XCTAssertEqual(second?.accessibilityValue() as? String, "focused")

    controller.focusPaneLeft(nil)

    XCTAssertEqual(first?.accessibilityValue() as? String, "focused")
    XCTAssertEqual(second?.accessibilityValue() as? String, "unfocused")
  }

  /// Catches a split that ignores the minimum pane size. The area is 960 wide with 5 point
  /// dividers. The first split leaves 477.5 each. The second splits pane 2 along the row, so the
  /// root has three children and two dividers: 950 is shared as 475, 237.5, and 237.5, and 237.5
  /// is above 200. Splitting pane 4 would leave four children and three dividers, so 945 is shared
  /// as 472.5, 236.25, 118.125, and 118.125. That is below 200, so it is refused, the applet made
  /// for it is closed, and the status bar says why.
  func testSplitBelowTheMinimumIsRefusedWithAMessage() throws {
    let controller = try makeController()
    controller.openPane(.terminalShell, axis: .row)
    XCTAssertNotNil(controller.openPane(.terminalShell, axis: .row))

    XCTAssertNil(controller.openPane(.terminalShell, axis: .row))

    XCTAssertEqual(controller.paneIDs.count, 3)
    XCTAssertEqual(made.count, 4)
    XCTAssertTrue(made[3].closed)
    XCTAssertEqual(controller.statusCenter.history.last?.level, .warning)
    XCTAssertTrue(
      controller.statusCenter.history.last?.text.contains("not enough room") ?? false)
  }

  /// Catches a program-mode choice that opens a pane the app cannot back. The factory refuses it,
  /// no pane appears, and the status bar says so.
  func testAnUnavailableChoiceOpensNoPane() throws {
    let controller = try makeController()

    XCTAssertNil(controller.openPane(.terminalProgram(command: "htop"), axis: .row))

    XCTAssertEqual(controller.paneIDs.count, 1)
    XCTAssertEqual(controller.statusCenter.history.last?.level, .error)
    XCTAssertTrue(controller.statusCenter.history.last?.text.contains("no programs") ?? false)
  }

  // MARK: Window size

  /// Catches a window whose minimum ignores the tree. One pane needs 200 wide and 100 high. A row
  /// split needs 200 + 5 + 200, so 405 wide. A column split under it needs 100 + 5 + 100 more
  /// high than a single row of panes, so the minimum height grows by 105.
  func testMinimumWindowSizeFollowsTheTree() throws {
    let controller = try makeController()
    let window = try XCTUnwrap(controller.window)
    let single = window.contentMinSize
    XCTAssertEqual(single.width, 200)

    controller.openPane(.terminalShell, axis: .row)
    XCTAssertEqual(window.contentMinSize.width, 405)
    XCTAssertEqual(window.contentMinSize.height, single.height)

    controller.openPane(.terminalShell, axis: .column)
    XCTAssertEqual(window.contentMinSize.width, 405)
    XCTAssertEqual(window.contentMinSize.height, single.height + 105)

    controller.closePane(nil)
    XCTAssertEqual(window.contentMinSize.height, single.height)
  }

  // MARK: Closing

  /// Catches a close that leaves a hole: the closed applet ends, the window stays, and the
  /// remaining pane takes the whole width and the focus.
  func testClosingAPaneGivesItsSpaceToTheNeighbor() throws {
    let controller = try makeController()
    controller.window?.orderFrontRegardless()
    defer { controller.window?.close() }
    controller.openPane(.terminalShell, axis: .row)

    controller.closePane(nil)

    XCTAssertEqual(controller.paneIDs, [NodeID(rawValue: 1)])
    XCTAssertEqual(controller.focusedPane, NodeID(rawValue: 1))
    XCTAssertTrue(made[1].closed)
    XCTAssertFalse(made[0].closed)
    XCTAssertEqual(width(controller, 1), 960)
    XCTAssertEqual(controller.window?.isVisible, true)
    XCTAssertEqual(controller.paneArea.dividers.count, 0)
    XCTAssertEqual(controller.paneArea.paneView(for: NodeID(rawValue: 1))?.showsFocusMarker, false)
  }

  /// Catches a pane exit that closes the whole window while other panes still run.
  func testAnAppletExitClosesOnlyItsPane() throws {
    let controller = try makeController()
    controller.window?.orderFrontRegardless()
    defer { controller.window?.close() }
    controller.openPane(.terminalShell, axis: .row)

    controller.appletDidExit(made[0])

    XCTAssertEqual(controller.paneIDs, [NodeID(rawValue: 2)])
    XCTAssertTrue(made[0].closed)
    XCTAssertFalse(made[1].closed)
    XCTAssertEqual(controller.window?.isVisible, true)
  }

  /// Catches a window close that leaves applets of other panes running.
  func testClosingTheWindowClosesEveryApplet() throws {
    let controller = try makeController()
    controller.openPane(.terminalShell, axis: .row)
    controller.openPane(.terminalShell, axis: .column)

    controller.window?.close()

    XCTAssertTrue(made.allSatisfy(\.closed))
  }

  /// Catches a focus jump. Pane 1's shell exits while pane 4 has the keyboard. Pane 4 keeps it.
  func testAnExitInAnUnfocusedPaneLeavesFocusAlone() throws {
    let controller = try makeController()
    controller.openPane(.terminalShell, axis: .row)
    controller.openPane(.terminalShell, axis: .row)
    XCTAssertEqual(
      controller.paneIDs, [NodeID(rawValue: 1), NodeID(rawValue: 2), NodeID(rawValue: 4)])
    XCTAssertEqual(controller.focusedPane, NodeID(rawValue: 4))

    controller.appletDidExit(made[0])

    XCTAssertEqual(controller.paneIDs, [NodeID(rawValue: 2), NodeID(rawValue: 4)])
    XCTAssertEqual(controller.focusedPane, NodeID(rawValue: 4))
    XCTAssertEqual(
      controller.paneArea.paneView(for: NodeID(rawValue: 4))?.accessibilityValue() as? String,
      "focused")
  }

  /// Catches the focused pane's close leaving focus nowhere useful: it goes to the neighbor.
  func testClosingTheFocusedPaneFocusesItsNeighbor() throws {
    let controller = try makeController()
    controller.openPane(.terminalShell, axis: .row)
    controller.openPane(.terminalShell, axis: .row)

    controller.closePane(nil)

    XCTAssertEqual(controller.focusedPane, NodeID(rawValue: 2))
  }

  /// Catches an applet that never starts because it shares an identity with one that closed. A
  /// closed applet's memory can be reused, and the new applet gets the same object identifier. The
  /// factory here hands the closed applet back to stand for that reuse.
  func testAnAppletWithAReusedIdentityStillStarts() throws {
    let controller = try makeController()
    controller.openPane(.terminalShell, axis: .row)
    let reused = made[1]
    XCTAssertTrue(reused.started)

    controller.closePane(nil)
    XCTAssertTrue(reused.closed)
    reused.started = false
    reuse = reused

    controller.openPane(.terminalShell, axis: .row)

    XCTAssertTrue(reused.started)
  }

  /// Catches pane actions that act on the window under a sheet. With the picker or an alert up,
  /// close and the focus moves do nothing, and their menu items are disabled. Cmd-W while the
  /// picker is open therefore does nothing. Escape cancels the picker.
  func testPaneActionsAreOffWhileASheetIsUp() throws {
    let controller = try makeController()
    controller.openPane(.terminalShell, axis: .row)
    let window = try XCTUnwrap(controller.window)
    window.orderFrontRegardless()
    defer { controller.window?.close() }

    let sheet = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.beginSheet(sheet)
    XCTAssertNotNil(window.attachedSheet)

    let before = controller.focusedPane
    controller.closePane(nil)
    controller.focusPaneLeft(nil)
    controller.focusNextPane(nil)
    controller.splitRight(nil)

    XCTAssertEqual(controller.paneIDs.count, 2)
    XCTAssertEqual(controller.focusedPane, before)

    let actions: [Selector] = [
      #selector(MainWindowController.closePane(_:)),
      #selector(MainWindowController.splitRight(_:)),
      #selector(MainWindowController.splitDown(_:)),
      #selector(MainWindowController.focusNextPane(_:)),
      #selector(MainWindowController.focusPreviousPane(_:)),
      #selector(MainWindowController.focusPaneLeft(_:)),
      #selector(MainWindowController.focusPaneRight(_:)),
      #selector(MainWindowController.focusPaneUp(_:)),
      #selector(MainWindowController.focusPaneDown(_:)),
    ]
    for action in actions {
      XCTAssertFalse(
        controller.validateMenuItem(NSMenuItem(title: "x", action: action, keyEquivalent: "")),
        "\(action) is live under a sheet")
    }

    window.endSheet(sheet)
    XCTAssertTrue(
      controller.validateMenuItem(
        NSMenuItem(
          title: "x", action: #selector(MainWindowController.closePane(_:)), keyEquivalent: "")))
  }

  // MARK: Focus and dividers

  /// Catches focus moves that ignore geometry. With pane 4 below pane 2, up from 4 reaches 2, left
  /// from 4 reaches 1, and next walks reading order.
  func testFocusMovesByDirectionAndOrder() throws {
    let controller = try makeController()
    controller.openPane(.terminalShell, axis: .row)
    controller.openPane(.terminalShell, axis: .column)
    XCTAssertEqual(controller.focusedPane, NodeID(rawValue: 4))

    controller.focusPaneUp(nil)
    XCTAssertEqual(controller.focusedPane, NodeID(rawValue: 2))

    controller.focusPaneDown(nil)
    controller.focusPaneLeft(nil)
    XCTAssertEqual(controller.focusedPane, NodeID(rawValue: 1))

    controller.focusNextPane(nil)
    XCTAssertEqual(controller.focusedPane, NodeID(rawValue: 2))

    controller.focusPreviousPane(nil)
    controller.focusPreviousPane(nil)
    XCTAssertEqual(controller.focusedPane, NodeID(rawValue: 4))
  }

  /// Catches a divider that does not resize the panes beside it. Dragging 100 points right of the
  /// divider's center grows pane 1 from 477.5 to 577.5 and shrinks pane 2 to 377.5.
  func testDraggingADividerResizesBothSides() throws {
    let controller = try makeController()
    controller.openPane(.terminalShell, axis: .row)

    let divider = try XCTUnwrap(controller.paneArea.dividers.first)
    XCTAssertEqual(divider.accessibilityIdentifier(), "divider-1-2")

    divider.onDrag?(divider, NSPoint(x: divider.frame.midX + 100, y: divider.frame.midY))

    XCTAssertEqual(width(controller, 1), 577.5, accuracy: 1)
    XCTAssertEqual(width(controller, 2), 377.5, accuracy: 1)
  }

  /// Catches a drag that crushes a pane. Pane 2 cannot go below 200, so the divider stops with
  /// pane 2 at 200 and pane 1 at 755.
  func testDraggingStopsAtTheMinimumPaneSize() throws {
    let controller = try makeController()
    controller.openPane(.terminalShell, axis: .row)

    let divider = try XCTUnwrap(controller.paneArea.dividers.first)
    divider.onDrag?(divider, NSPoint(x: 5000, y: divider.frame.midY))

    XCTAssertEqual(width(controller, 2), 200, accuracy: 1)
    XCTAssertEqual(width(controller, 1), 755, accuracy: 1)
  }
}

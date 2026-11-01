import AppKit
import AppletKit
import PaneModel
import Preferences
import StatusKit
import XCTest

@testable import WindowKit

/// Holds the wakeups the undo timer asks for, so a test fires them by hand. A cancelled wake is
/// gone, as with a real timer.
@MainActor
final class WakeScheduler {
  private var counter = 0
  private(set) var pending: [Int: (delay: TimeInterval, action: @MainActor () -> Void)] = [:]

  func schedule(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void)
    -> @MainActor ()
    -> Void
  {
    counter += 1
    let id = counter
    pending[id] = (delay, action)

    return { [weak self] in self?.pending[id] = nil }
  }

  /// Runs the one pending wake, if there is one.
  func fire() {
    guard let id = pending.keys.min(), let entry = pending.removeValue(forKey: id) else { return }

    entry.action()
  }
}

@MainActor
final class UndoRecorder {
  var made: [FakeApplet] = []
  var restored: [FakeApplet] = []
  var asked: [CloseConfirmation] = []

  /// The answers to the questions, in order. A question with no answer left is declined.
  var answers: [Bool] = []
}

/// One window over fake applets, a manual clock, a scheduler held by hand, and a confirmer that
/// records what it was asked and answers from a script. The applets are titled "Fake 0",
/// "Fake 1", and so on in the order made.
@MainActor
final class UndoFixture {
  let suite = "uniterm-undo-test-\(UUID().uuidString)"
  let defaults: UserDefaults
  let clock = TestClock()
  let scheduler = WakeScheduler()
  let recorder = UndoRecorder()
  let controller: MainWindowController

  init(policy: CloseUndoPolicy = .standard) throws {
    let defaults = UserDefaults(suiteName: suite)!
    let store = SettingsStore(defaults: defaults)
    let recorder = recorder

    self.defaults = defaults

    controller = try MainWindowController(
      appearance: AppearanceController(store: store), settings: store, undoPolicy: policy,
      undoClock: clock, undoScheduler: scheduler.schedule,
      restoreApplet: { description in
        guard case .string(let title) = description.payload else {
          throw AppletRestoreError.corrupt("no title")
        }

        let applet = FakeApplet()
        applet.title = title
        recorder.restored.append(applet)
        return applet
      },
      makeApplet: { _ in
        let applet = FakeApplet()
        applet.title = "Fake \(recorder.made.count)"
        recorder.made.append(applet)
        return applet
      })

    controller.confirmer = { request, _ in
      recorder.asked.append(request)
      return recorder.answers.isEmpty ? false : recorder.answers.removeFirst()
    }

    controller.window?.contentView?.layoutSubtreeIfNeeded()
  }

  func cleanUp() {
    controller.window?.close()
    defaults.removePersistentDomain(forName: suite)
  }

  var made: [FakeApplet] { recorder.made }
  var bar: StatusBarView { controller.contentController.statusBar }
  var graceText: String? { bar.segments.first { $0.id == .grace }?.text }

  /// Opens panes until there are `count`. The first three sit in a row, as panes 1, 2, and 4. The
  /// fourth splits pane 4 downward as pane 5, since a fourth pane in the row would be too narrow.
  func openPanes(_ count: Int) {
    precondition(count <= 4, "the window has room for four panes")

    while controller.paneIDs.count < count {
      let axis: Axis = controller.paneIDs.count < 3 ? .row : .column
      precondition(controller.openPane(.terminalShell, axis: axis) != nil, "a pane did not open")
    }
  }

  /// Waits for the question the window is asking, if any, to be answered and acted on.
  func settle() async {
    let task = controller.pendingGuard
    await task?.value
  }

  func hasSegment(_ id: BarSegmentID) -> Bool {
    bar.segments.contains { $0.id == id }
  }
}

@MainActor
final class UndoCloseTests: XCTestCase {
  private var fixtures: [UndoFixture] = []

  override func tearDown() async throws {
    for fixture in fixtures {
      fixture.cleanUp()
    }

    fixtures = []
  }

  private func makeFixture(_ policy: CloseUndoPolicy = .standard) throws -> UndoFixture {
    let fixture = try UndoFixture(policy: policy)
    fixtures.append(fixture)
    return fixture
  }

  private func id(_ value: UInt64) -> NodeID { NodeID(rawValue: value) }

  private func rootWeights(_ controller: MainWindowController) -> [Double] {
    guard case .split(let split) = controller.paneArea.tree.root else { return [] }
    return split.children.map(\.weight)
  }

  // MARK: Grace tier

  /// Catches a close that tears the applet down at once, so undo has no live session to bring
  /// back. The closed pane's applet is detached, alive, and the bar shows the grace period. The
  /// clock reads 0 and the period is 10 seconds, so 10 are left.
  func testClosingAPaneKeepsItsAppletAliveAndHidden() throws {
    let fixture = try makeFixture()
    fixture.openPanes(2)

    fixture.controller.closePane(nil)

    XCTAssertEqual(fixture.controller.paneIDs, [id(1)])
    XCTAssertEqual(fixture.made[1].detachCount, 1)
    XCTAssertFalse(fixture.made[1].closed)
    XCTAssertEqual(fixture.controller.ledger.hidden.count, 1)
    XCTAssertEqual(fixture.graceText, "1 closed pane kept for 10s. Cmd-Z undoes")
    XCTAssertTrue(fixture.hasSegment(.graceHangUp))
  }

  /// Catches an undo that brings back a new applet or a new ID instead of the exact session. The
  /// pane returns with ID 2 and the same applet object. No applet is made, and none is restored
  /// from a description. The two panes share the row evenly again.
  func testUndoWithinGraceReattachesTheSameAppletAndID() throws {
    let fixture = try makeFixture()
    fixture.openPanes(2)
    fixture.controller.closePane(nil)

    fixture.controller.undoClosePane(nil)

    XCTAssertEqual(fixture.controller.paneIDs, [id(1), id(2)])
    XCTAssertTrue(fixture.controller.paneArea.applet(for: id(2)) === fixture.made[1])
    XCTAssertEqual(fixture.made[1].reattachCount, 1)
    XCTAssertFalse(fixture.made[1].closed)
    XCTAssertEqual(fixture.made.count, 2)
    XCTAssertTrue(fixture.recorder.restored.isEmpty)
    XCTAssertEqual(rootWeights(fixture.controller), [0.5, 0.5])
    XCTAssertEqual(fixture.controller.focusedPane, id(2))
    XCTAssertTrue(fixture.controller.ledger.hidden.isEmpty)
    XCTAssertFalse(fixture.hasSegment(.grace))
  }

  /// Catches a countdown that never moves, and a deadline that does not hang the pane up. At 3
  /// seconds, 7 are left. At 10 the pane is hung up, its description stays, the segment goes, and no
  /// wake is left pending.
  func testTheGracePeriodCountsDownAndHangsUpAtTheDeadline() throws {
    let fixture = try makeFixture()
    fixture.openPanes(2)
    fixture.controller.closePane(nil)

    fixture.clock.now = 3
    fixture.scheduler.fire()

    XCTAssertEqual(fixture.graceText, "1 closed pane kept for 7s. Cmd-Z undoes")
    XCTAssertFalse(fixture.made[1].closed)

    fixture.clock.now = 10
    fixture.scheduler.fire()

    XCTAssertTrue(fixture.made[1].closed)
    XCTAssertTrue(fixture.controller.ledger.hidden.isEmpty)
    XCTAssertEqual(fixture.controller.ledger.described.count, 1)
    XCTAssertFalse(fixture.hasSegment(.grace))
    XCTAssertTrue(fixture.scheduler.pending.isEmpty)
  }

  /// Catches a reopen that reuses the old ID or makes the applet through the picker's factory.
  /// Panes 1 and 2 and split 3 were issued, so the reopened pane is 4. It comes from the saved
  /// description, which carries the old applet's title.
  func testUndoAfterTheGracePeriodReopensFromTheDescriptionWithANewID() throws {
    let fixture = try makeFixture()
    fixture.openPanes(2)
    fixture.controller.closePane(nil)
    fixture.clock.now = 10
    fixture.scheduler.fire()

    fixture.controller.undoClosePane(nil)

    XCTAssertEqual(fixture.controller.paneIDs, [id(1), id(4)])
    XCTAssertEqual(fixture.recorder.restored.map(\.title), ["Fake 1"])
    XCTAssertTrue(fixture.controller.paneArea.applet(for: id(4)) === fixture.recorder.restored[0])
    XCTAssertTrue(fixture.recorder.restored[0].started)
    XCTAssertEqual(fixture.made.count, 2)
    XCTAssertTrue(fixture.controller.ledger.described.isEmpty)
    XCTAssertEqual(fixture.controller.focusedPane, id(4))
  }

  /// Catches an undo that drops a description this build cannot restore. A placeholder closed past
  /// its grace period holds a newer build's bytes. The reopened pane is a placeholder that still
  /// holds them, so a later save writes them back.
  func testUndoOfADescriptionTheRestorerRefusesKeepsItsBytesInAPlaceholder() throws {
    let fixture = try makeFixture()
    fixture.openPanes(2)

    let bytes = Data(#"{"type":"fake","version":9,"payload":{"new":true}}"#.utf8)
    fixture.made[1].fixedDescription = AppletDescription(
      type: "fake", version: 9, payload: .null, verbatim: bytes)
    fixture.controller.closePane(nil)
    fixture.clock.now = 10
    fixture.scheduler.fire()

    fixture.controller.undoClosePane(nil)

    XCTAssertEqual(fixture.controller.paneIDs.count, 2)

    let reopened = fixture.controller.paneIDs.compactMap {
      fixture.controller.paneArea.applet(for: $0) as? PlaceholderApplet
    }

    XCTAssertEqual(reopened.count, 1)
    XCTAssertEqual(reopened.first?.describe().verbatim, bytes)
    XCTAssertTrue(fixture.controller.ledger.described.isEmpty)
  }

  /// Catches an undo that takes the hidden tier before the stack whatever the order of closes. Pane
  /// 4 closes first and ages into a description. Pane 2 closes later and is still hidden. The first
  /// undo returns pane 2 with its ID. The second reopens pane 4's description after pane 2, as
  /// pane 6, since 5 went to the split that wrapped pane 1 for the first undo.
  func testUndoTakesTheNewestCloseAcrossBothTiers() throws {
    let fixture = try makeFixture()
    fixture.openPanes(3)
    XCTAssertEqual(fixture.controller.paneIDs, [id(1), id(2), id(4)])

    fixture.controller.closePane(nil)
    fixture.clock.now = 10
    fixture.scheduler.fire()
    fixture.controller.closePane(nil)

    fixture.controller.undoClosePane(nil)
    XCTAssertEqual(fixture.controller.paneIDs, [id(1), id(2)])
    XCTAssertTrue(fixture.recorder.restored.isEmpty)

    fixture.controller.undoClosePane(nil)
    XCTAssertEqual(fixture.controller.paneIDs, [id(1), id(2), id(6)])
    XCTAssertEqual(fixture.recorder.restored.map(\.title), ["Fake 2"])
  }

  /// Catches undo that ignores where the pane sat when the tree has changed since. Pane 2 closes,
  /// then pane 1 is split below, so pane 1 sits in a column. Pane 2 still returns beside pane 1 in
  /// a row, not below it.
  func testUndoPlacesThePaneBesideItsNeighborAfterTheNeighborMoved() throws {
    let fixture = try makeFixture()
    fixture.openPanes(2)
    fixture.controller.closePane(nil)
    fixture.controller.focusPaneLeft(nil)
    XCTAssertNotNil(fixture.controller.openPane(.terminalShell, axis: .column))

    fixture.controller.undoClosePane(nil)

    guard case .split(let column) = fixture.controller.paneArea.tree.root else {
      return XCTFail("the root is a pane")
    }

    XCTAssertEqual(column.axis, .column)
    guard case .split(let row) = column.children[0].node else {
      return XCTFail("pane 1 was not wrapped in a row")
    }

    XCTAssertEqual(row.axis, .row)
    XCTAssertEqual(row.children.map { $0.node.id }, [id(1), id(2)])
  }

  /// Catches an undo that cannot place a pane whose neighbor has gone. Pane 2 closes beside pane 1.
  /// Then pane 1's shell exits, which retires 1 and leaves only pane 4. Pane 2 returns at the end
  /// of the row, on the side it was recorded on, with its ID.
  func testUndoFallsBackToTheEdgeWhenTheNeighborIsGone() throws {
    let fixture = try makeFixture()
    fixture.openPanes(3)
    XCTAssertEqual(fixture.controller.paneIDs, [id(1), id(2), id(4)])
    fixture.controller.focusPaneLeft(nil)
    fixture.controller.closePane(nil)
    fixture.controller.appletDidExit(fixture.made[0])
    XCTAssertEqual(fixture.controller.paneIDs, [id(4)])

    fixture.controller.undoClosePane(nil)

    XCTAssertEqual(fixture.controller.paneIDs, [id(4), id(2)])
    XCTAssertTrue(fixture.controller.paneArea.applet(for: id(2)) === fixture.made[1])
    XCTAssertTrue(fixture.controller.ledger.hidden.isEmpty)
  }

  // MARK: Slots

  /// Catches a tier that grows past its slots, and a dialog that comes before an idle hidden pane
  /// frees a slot. With two slots and three closes of idle panes, the oldest hidden pane is hung up
  /// to make room, two stay hidden, and nothing is asked.
  func testTheNumberOfHiddenPanesIsBoundedAndTheOldestIdleOneIsDroppedFirst() throws {
    let fixture = try makeFixture(
      CloseUndoPolicy(graceSlots: 2, gracePeriod: 10, stackDepth: 20))
    fixture.openPanes(4)
    XCTAssertEqual(fixture.controller.paneIDs, [id(1), id(2), id(4), id(5)])

    for _ in 0..<3 {
      fixture.controller.closePane(nil)
    }

    XCTAssertEqual(fixture.controller.ledger.hidden.count, 2)
    XCTAssertTrue(fixture.made[3].closed, "the oldest hidden pane stayed alive")
    XCTAssertFalse(fixture.made[2].closed)
    XCTAssertFalse(fixture.made[1].closed)
    XCTAssertEqual(fixture.controller.ledger.described.count, 1)
    XCTAssertTrue(fixture.recorder.asked.isEmpty)
  }

  /// Catches a full tier that ends a running hidden pane to make room. The hidden pane is running,
  /// and the pane that closes now is idle. No dialog is needed, since the idle pane loses nothing
  /// but its session. It is hung up and described, and the running pane stays hidden.
  func testAnIdlePaneNeverEvictsARunningHiddenPane() throws {
    let fixture = try makeFixture(
      CloseUndoPolicy(graceSlots: 1, gracePeriod: 10, stackDepth: 20))
    fixture.openPanes(3)
    fixture.made[2].isRunningSomething = true

    fixture.controller.closePane(nil)
    fixture.controller.closePane(nil)

    XCTAssertTrue(fixture.recorder.asked.isEmpty)
    XCTAssertTrue(fixture.made[1].closed)
    XCTAssertFalse(fixture.made[2].closed)
    XCTAssertEqual(fixture.controller.ledger.hidden.count, 1)
    XCTAssertTrue(fixture.controller.ledger.hidden[0].applet === fixture.made[2])
    XCTAssertEqual(fixture.controller.ledger.described.count, 1)
  }

  /// Catches a dialog that appears when an idle hidden pane could have been dropped instead. The
  /// hidden pane is idle and the closing pane is running. The idle one drops to its description,
  /// and the running one takes the slot with no question.
  func testAnIdleHiddenPaneIsDroppedBeforeAnyDialogIsShown() throws {
    let fixture = try makeFixture(
      CloseUndoPolicy(graceSlots: 1, gracePeriod: 10, stackDepth: 20))
    fixture.openPanes(3)
    fixture.made[1].isRunningSomething = true

    fixture.controller.closePane(nil)
    fixture.controller.closePane(nil)

    XCTAssertTrue(fixture.recorder.asked.isEmpty)
    XCTAssertTrue(fixture.made[2].closed)
    XCTAssertFalse(fixture.made[1].closed)
    XCTAssertTrue(fixture.controller.ledger.hidden[0].applet === fixture.made[1])
  }

  /// Catches a close that ends a running pane with no question when no slot is free, and one that
  /// ends it anyway after Cancel. Both hidden and closing panes are running. The question names the
  /// running tab. Declining keeps the pane in the tree. Accepting hangs it up.
  func testClosingARunningPaneWithNoFreeSlotAsksAndCancelKeepsIt() async throws {
    let fixture = try makeFixture(
      CloseUndoPolicy(graceSlots: 1, gracePeriod: 10, stackDepth: 20))
    fixture.openPanes(3)
    fixture.made[1].isRunningSomething = true
    fixture.made[2].isRunningSomething = true
    fixture.controller.closePane(nil)
    XCTAssertTrue(fixture.recorder.asked.isEmpty, "a free slot still asked")

    fixture.recorder.answers = [false]
    fixture.controller.closePane(nil)
    await fixture.settle()

    XCTAssertEqual(fixture.recorder.asked.count, 1)
    XCTAssertEqual(fixture.recorder.asked[0].labels, ["Fake 1"])
    XCTAssertEqual(fixture.controller.paneIDs, [id(1), id(2)])
    XCTAssertFalse(fixture.made[1].closed)

    fixture.recorder.answers = [true]
    fixture.controller.closePane(nil)
    await fixture.settle()

    XCTAssertEqual(fixture.recorder.asked.count, 2)
    XCTAssertEqual(fixture.controller.paneIDs, [id(1)])
    XCTAssertTrue(fixture.made[1].closed)
    XCTAssertFalse(fixture.made[2].closed)
    XCTAssertEqual(fixture.controller.ledger.described.count, 1)
  }

  /// Catches a close that asks although the grace tier can undo it. A running pane closes with free
  /// slots and no question.
  func testClosingARunningPaneWithAFreeSlotNeverAsks() throws {
    let fixture = try makeFixture()
    fixture.openPanes(2)
    fixture.made[1].isRunningSomething = true

    fixture.controller.closePane(nil)

    XCTAssertTrue(fixture.recorder.asked.isEmpty)
    XCTAssertFalse(fixture.made[1].closed)
    XCTAssertEqual(fixture.controller.ledger.hidden.count, 1)
  }

  /// Catches a stack that grows past its depth. With one slot and a depth of 1, three closes of
  /// idle panes hang up the first two. The newest of those, "Fake 2", is the one description left,
  /// and "Fake 1" is still hidden.
  func testTheDescriptionStackKeepsOnlyTheNewestCloses() throws {
    let fixture = try makeFixture(
      CloseUndoPolicy(graceSlots: 1, gracePeriod: 10, stackDepth: 1))
    fixture.openPanes(4)

    for _ in 0..<3 {
      fixture.controller.closePane(nil)
    }

    XCTAssertEqual(fixture.controller.paneIDs, [id(1)])
    XCTAssertTrue(fixture.made[3].closed)
    XCTAssertEqual(fixture.controller.ledger.described.map(\.title), ["Fake 2"])
    XCTAssertTrue(fixture.controller.ledger.hidden[0].applet === fixture.made[1])
  }

  // MARK: Exits

  /// Catches a shell that exits on its own and leaves a hidden session or a description behind. The
  /// user did not close this pane, so undo has nothing to bring back.
  func testAPaneThatExitedOnItsOwnAddsNothingToEitherTier() throws {
    let fixture = try makeFixture()
    fixture.openPanes(2)

    fixture.controller.appletDidExit(fixture.made[1])

    XCTAssertEqual(fixture.controller.paneIDs, [id(1)])
    XCTAssertTrue(fixture.made[1].closed)
    XCTAssertTrue(fixture.controller.ledger.hidden.isEmpty)
    XCTAssertTrue(fixture.controller.ledger.described.isEmpty)
    XCTAssertFalse(fixture.hasSegment(.grace))
  }

  /// Catches a hidden pane that stays alive after its processes all exit. It drops to its
  /// description, and undo then reopens it with a new ID.
  func testAHiddenPaneWhoseProcessesAllExitDropsToItsDescription() throws {
    let fixture = try makeFixture()
    fixture.openPanes(2)
    fixture.controller.closePane(nil)

    fixture.controller.appletDidExit(fixture.made[1])

    XCTAssertTrue(fixture.made[1].closed)
    XCTAssertTrue(fixture.controller.ledger.hidden.isEmpty)
    XCTAssertEqual(fixture.controller.ledger.described.count, 1)
    XCTAssertFalse(fixture.hasSegment(.grace))

    fixture.controller.undoClosePane(nil)

    XCTAssertEqual(fixture.recorder.restored.map(\.title), ["Fake 1"])
    XCTAssertEqual(fixture.controller.paneIDs, [id(1), id(4)])
  }

  /// Catches a hidden applet whose message loses its pane. It still names pane 2.
  func testAHiddenPanesMessageStillNamesItsPane() throws {
    let fixture = try makeFixture()
    fixture.openPanes(2)
    fixture.controller.closePane(nil)

    fixture.controller.applet(fixture.made[1], post: .info, text: "done")

    XCTAssertEqual(
      fixture.controller.statusCenter.history.last?.source, .pane(id: 2, name: "Fake 1"))
  }

  // MARK: Status bar

  /// Catches a flood of messages that pushes the grace segment off the bar. Thirty messages and an
  /// error arrive, and the segment and its hang-up control are still there.
  func testTheGraceSegmentStaysThroughAMessageFlood() throws {
    let fixture = try makeFixture()
    fixture.openPanes(2)
    fixture.controller.closePane(nil)

    for index in 0..<30 {
      fixture.controller.statusCenter.post(
        level: .info, source: .uniterm, text: "message \(index)")
    }

    fixture.controller.statusCenter.post(level: .error, source: .uniterm, text: "boom")

    XCTAssertTrue(fixture.hasSegment(.grace))
    XCTAssertTrue(fixture.hasSegment(.graceHangUp))
    XCTAssertEqual(fixture.graceText, "1 closed pane kept for 10s. Cmd-Z undoes")
  }

  /// Catches a hang-up control that does nothing. Clicking it ends the hidden pane at once, ahead
  /// of its deadline, and keeps its description so undo can still reopen the layout.
  func testTheHangUpControlEndsHiddenPanesAtOnce() throws {
    let fixture = try makeFixture()
    fixture.openPanes(3)
    fixture.controller.closePane(nil)
    fixture.controller.closePane(nil)
    XCTAssertEqual(fixture.controller.ledger.hidden.count, 2)

    let window = try XCTUnwrap(fixture.controller.window)
    fixture.bar.layoutSubtreeIfNeeded()
    let frame = try XCTUnwrap(fixture.bar.frame(of: .graceHangUp))
    let event = try XCTUnwrap(
      NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: fixture.bar.convert(NSPoint(x: frame.midX, y: frame.midY), to: nil),
        modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
        eventNumber: 0, clickCount: 1, pressure: 1))

    fixture.bar.mouseDown(with: event)

    XCTAssertTrue(fixture.controller.ledger.hidden.isEmpty)
    XCTAssertTrue(fixture.made[1].closed)
    XCTAssertTrue(fixture.made[2].closed)
    XCTAssertEqual(fixture.controller.ledger.described.count, 2)
    XCTAssertFalse(fixture.hasSegment(.grace))
    XCTAssertTrue(fixture.scheduler.pending.isEmpty)
  }

  // MARK: Window close guard

  /// Catches a window close that asks although nothing is running.
  func testClosingAnIdleWindowAsksNothing() throws {
    let fixture = try makeFixture()
    let window = try XCTUnwrap(fixture.controller.window)

    XCTAssertTrue(fixture.controller.windowShouldClose(window))
    XCTAssertTrue(fixture.recorder.asked.isEmpty)
  }

  /// Catches a window that closes with a program running and no question. The question names the
  /// tab. Cancel keeps the window and everything in it.
  func testClosingAWindowWithARunningTabAsksAndCancelKeepsTheWindow() async throws {
    let fixture = try makeFixture()
    let window = try XCTUnwrap(fixture.controller.window)
    window.orderFrontRegardless()
    fixture.made[0].isRunningSomething = true
    fixture.made[0].labels = ["vim notes.txt"]

    XCTAssertFalse(fixture.controller.windowShouldClose(window))
    await fixture.settle()

    XCTAssertEqual(fixture.recorder.asked.count, 1)
    XCTAssertEqual(fixture.recorder.asked[0].labels, ["vim notes.txt"])
    XCTAssertEqual(fixture.recorder.asked[0].confirmTitle, "Close Window")
    XCTAssertTrue(window.isVisible)
    XCTAssertFalse(fixture.made[0].closed)
  }

  /// Catches a confirmed close that leaves the window open.
  func testConfirmingTheWindowCloseClosesTheWindowAndItsApplets() async throws {
    let fixture = try makeFixture()
    let window = try XCTUnwrap(fixture.controller.window)
    window.orderFrontRegardless()
    fixture.made[0].isRunningSomething = true
    fixture.recorder.answers = [true]

    XCTAssertFalse(fixture.controller.windowShouldClose(window))
    await fixture.settle()

    XCTAssertFalse(window.isVisible)
    XCTAssertTrue(fixture.made[0].closed)
  }

  /// Catches a window close that forgets hidden panes. The visible pane is idle and the hidden one
  /// runs vim, so the window still asks and names the hidden tab. Confirming hangs the hidden
  /// pane up.
  func testAHiddenRunningPaneCountsInTheWindowCloseGuard() async throws {
    let fixture = try makeFixture()
    let window = try XCTUnwrap(fixture.controller.window)
    window.orderFrontRegardless()
    fixture.openPanes(2)
    fixture.made[1].isRunningSomething = true
    fixture.made[1].labels = ["vim"]
    fixture.controller.closePane(nil)
    fixture.recorder.answers = [true]

    XCTAssertFalse(fixture.controller.windowShouldClose(window))
    await fixture.settle()

    XCTAssertEqual(fixture.recorder.asked.map(\.labels), [["vim"]])
    XCTAssertFalse(window.isVisible)
    XCTAssertTrue(fixture.made[1].closed)
  }

  /// Catches an idle hidden pane that blocks a window close with a question.
  func testAnIdleHiddenPaneDoesNotAskOnWindowClose() throws {
    let fixture = try makeFixture()
    let window = try XCTUnwrap(fixture.controller.window)
    fixture.openPanes(2)
    fixture.controller.closePane(nil)

    XCTAssertTrue(fixture.controller.windowShouldClose(window))
    XCTAssertTrue(fixture.recorder.asked.isEmpty)
  }

  /// Catches a multi-tab pane that is named as one. A pane with three tabs, one running, lists the
  /// running tab alone.
  func testAMultiTabPaneIsNamedByItsRunningTabs() async throws {
    let fixture = try makeFixture()
    let window = try XCTUnwrap(fixture.controller.window)
    window.orderFrontRegardless()
    fixture.made[0].tabCount = 3
    fixture.made[0].isRunningSomething = true
    fixture.made[0].labels = ["make test"]

    XCTAssertFalse(fixture.controller.windowShouldClose(window))
    await fixture.settle()

    XCTAssertEqual(fixture.recorder.asked.map(\.labels), [["make test"]])
  }

  // MARK: Last visible pane

  /// Catches a last-pane close that ignores a hidden running pane. Pane 2 runs vim and is hidden.
  /// Closing pane 1, the last visible one, asks. Cancel brings pane 2 back in its place with its
  /// session, and the window stays open with pane 1.
  func testClosingTheLastVisiblePaneAsksAndCancelReattachesTheHiddenPane() async throws {
    let fixture = try makeFixture()
    let window = try XCTUnwrap(fixture.controller.window)
    window.orderFrontRegardless()
    fixture.openPanes(2)
    fixture.made[1].isRunningSomething = true
    fixture.controller.closePane(nil)
    XCTAssertEqual(fixture.controller.paneIDs, [id(1)])

    fixture.controller.closePane(nil)
    await fixture.settle()

    XCTAssertEqual(fixture.recorder.asked.map(\.labels), [["Fake 1"]])
    XCTAssertEqual(fixture.controller.paneIDs, [id(1), id(2)])
    XCTAssertTrue(fixture.controller.paneArea.applet(for: id(2)) === fixture.made[1])
    XCTAssertEqual(fixture.made[1].reattachCount, 1)
    XCTAssertFalse(fixture.made[1].closed)
    XCTAssertTrue(window.isVisible)
  }

  /// Catches a confirmed last-pane close that leaves the hidden process alive. Confirming closes the
  /// window and hangs up both applets.
  func testConfirmingTheLastPaneCloseHangsUpTheHiddenPaneToo() async throws {
    let fixture = try makeFixture()
    let window = try XCTUnwrap(fixture.controller.window)
    window.orderFrontRegardless()
    fixture.openPanes(2)
    fixture.made[1].isRunningSomething = true
    fixture.controller.closePane(nil)
    fixture.recorder.answers = [true]

    fixture.controller.closePane(nil)
    await fixture.settle()

    XCTAssertFalse(window.isVisible)
    XCTAssertTrue(fixture.made[0].closed)
    XCTAssertTrue(fixture.made[1].closed)
  }

  /// Catches an idle last pane that asks, or a close that leaves the window open. Nothing is
  /// running, so the window closes at once.
  func testClosingTheLastIdlePaneClosesTheWindowWithoutAsking() throws {
    let fixture = try makeFixture()
    let window = try XCTUnwrap(fixture.controller.window)
    window.orderFrontRegardless()

    fixture.controller.closePane(nil)

    XCTAssertFalse(window.isVisible)
    XCTAssertTrue(fixture.recorder.asked.isEmpty)
    XCTAssertTrue(fixture.made[0].closed)
  }

  /// Catches a shell that exits as the last visible pane and takes a hidden running pane with it.
  /// Cancel brings the hidden pane back, then the exited pane leaves.
  func testTheLastVisiblePaneExitingWithAHiddenRunningPaneAsksFirst() async throws {
    let fixture = try makeFixture()
    let window = try XCTUnwrap(fixture.controller.window)
    window.orderFrontRegardless()
    fixture.openPanes(2)
    fixture.made[1].isRunningSomething = true
    fixture.controller.closePane(nil)

    fixture.controller.appletDidExit(fixture.made[0])
    await fixture.settle()

    XCTAssertEqual(fixture.recorder.asked.map(\.labels), [["Fake 1"]])
    XCTAssertEqual(fixture.controller.paneIDs, [id(2)])
    XCTAssertTrue(fixture.made[0].closed)
    XCTAssertFalse(fixture.made[1].closed)
    XCTAssertTrue(window.isVisible)
  }

  /// Catches an exit that arrives while the window-close question is open and is dropped. The last
  /// visible shell exits after Cmd-W asked about the hidden running pane. Cancel brings the hidden
  /// pane back, and the dead pane must leave too instead of staying as a zombie.
  func testALastPaneThatExitsWhileTheWindowQuestionIsOpenLeavesOnCancel() async throws {
    let fixture = try makeFixture()
    let window = try XCTUnwrap(fixture.controller.window)
    window.orderFrontRegardless()
    fixture.openPanes(2)
    fixture.made[1].isRunningSomething = true
    fixture.controller.closePane(nil)

    fixture.controller.closePane(nil)
    XCTAssertNotNil(fixture.controller.pendingGuard)

    fixture.controller.appletDidExit(fixture.made[0])
    await fixture.settle()

    XCTAssertEqual(fixture.recorder.asked.count, 1)
    XCTAssertEqual(fixture.controller.paneIDs, [id(2)])
    XCTAssertTrue(fixture.made[0].closed)
    XCTAssertFalse(fixture.made[1].closed)
    XCTAssertTrue(window.isVisible)
  }

  /// Catches a discarded pane whose ID can return. Hanging up the hidden pane retires its ID. The
  /// area then refuses to insert it, and a pane opened later gets a fresh ID.
  func testAHungUpPanesIDIsRetiredForGood() throws {
    let fixture = try makeFixture()
    fixture.openPanes(2)
    fixture.controller.closePane(nil)
    let closed = try XCTUnwrap(fixture.controller.ledger.hidden.first)

    fixture.controller.hangUpHiddenPanes()

    XCTAssertThrowsError(
      try fixture.controller.paneArea.insert(
        FakeApplet(), as: closed.closed.paneID, at: closed.closed.placement)
    ) { error in
      XCTAssertEqual(error as? PaneTreeError, .retired(closed.closed.paneID))
    }

    XCTAssertEqual(fixture.controller.paneIDs, [id(1)])
    fixture.controller.undoClosePane(nil)
    XCTAssertEqual(fixture.controller.paneIDs.count, 2)
    XCTAssertFalse(fixture.controller.paneIDs.contains(closed.closed.paneID))
  }

  /// Catches an exited last pane that is left dead after a cancel that cannot restore the hidden
  /// pane. The window is too narrow for two panes, so the hidden pane stays hidden and the dead
  /// pane stays so the window is not left empty. Once the window is wide enough, undo brings the
  /// hidden pane back and the dead pane leaves.
  func testADeadLastPaneLeavesWhenTheHiddenPaneFinallyReturns() async throws {
    let fixture = try makeFixture()
    let window = try XCTUnwrap(fixture.controller.window)
    window.orderFrontRegardless()
    fixture.openPanes(2)
    fixture.made[1].isRunningSomething = true
    fixture.controller.closePane(nil)
    window.setContentSize(NSSize(width: 300, height: 640))
    window.contentView?.layoutSubtreeIfNeeded()

    fixture.controller.appletDidExit(fixture.made[0])
    await fixture.settle()

    XCTAssertEqual(fixture.controller.paneIDs, [id(1)])
    XCTAssertEqual(fixture.controller.ledger.hidden.count, 1)
    XCTAssertTrue(window.isVisible)

    window.setContentSize(NSSize(width: 960, height: 640))
    window.contentView?.layoutSubtreeIfNeeded()
    fixture.controller.undoClosePane(nil)

    XCTAssertEqual(fixture.controller.paneIDs, [id(2)])
    XCTAssertTrue(fixture.made[0].closed)
    XCTAssertFalse(fixture.made[1].closed)
  }

  // MARK: Window lifecycle

  /// Catches a hidden pane that outlives its window, and a wake that fires on a closed window. The
  /// window closes with one pane hidden and one described. Both are gone, and no wake is pending.
  func testClosingTheWindowHangsUpHiddenPanesAndClearsTheUndoState() throws {
    let fixture = try makeFixture()
    fixture.openPanes(3)
    fixture.controller.closePane(nil)
    fixture.clock.now = 10
    fixture.scheduler.fire()
    fixture.controller.closePane(nil)
    XCTAssertEqual(fixture.controller.ledger.hidden.count, 1)
    XCTAssertEqual(fixture.controller.ledger.described.count, 1)

    fixture.controller.window?.close()

    XCTAssertTrue(fixture.made.allSatisfy(\.closed))
    XCTAssertTrue(fixture.controller.ledger.hidden.isEmpty)
    XCTAssertTrue(fixture.controller.ledger.described.isEmpty)
    XCTAssertTrue(fixture.scheduler.pending.isEmpty)
  }

  /// Catches a closed window that is kept alive by its grace panes or its timer. The controller is
  /// released after the window closes with hidden and described panes.
  func testAWindowWithUndoStateIsReleasedWhenItCloses() async throws {
    weak var released: MainWindowController?

    do {
      let fixture = try UndoFixture()
      fixture.openPanes(3)
      fixture.controller.closePane(nil)
      fixture.clock.now = 10
      fixture.scheduler.fire()
      fixture.controller.closePane(nil)
      released = fixture.controller

      fixture.cleanUp()
    }

    let gone = await waitUntil { released == nil }
    XCTAssertTrue(gone, "the closed window's controller was never released")
  }

  /// Catches a refused reopen that eats the description. With the window too narrow for another
  /// pane, undo posts a warning and the entry stays for a larger window.
  func testAnUndoThatDoesNotFitKeepsTheEntry() throws {
    let fixture = try makeFixture()
    fixture.openPanes(2)
    fixture.controller.closePane(nil)
    let window = try XCTUnwrap(fixture.controller.window)
    window.setContentSize(NSSize(width: 300, height: 640))
    window.contentView?.layoutSubtreeIfNeeded()

    fixture.controller.undoClosePane(nil)

    XCTAssertEqual(fixture.controller.paneIDs, [id(1)])
    XCTAssertEqual(fixture.controller.ledger.hidden.count, 1)
    XCTAssertEqual(
      fixture.controller.statusCenter.history.last?.text,
      "There is not enough room to bring the pane back.")
  }

  // MARK: Cmd-Z

  /// Catches Cmd-Z bound to a private selector. The menu item must send the standard undo selector,
  /// so the text controls of other windows keep their Cmd-Z.
  func testTheUndoItemSendsTheStandardUndoSelector() {
    XCTAssertEqual(#selector(MainWindow.undoCloseOrEdit(_:)), NSSelectorFromString("undo:"))
  }

  private final class PlainView: NSView {
    override var acceptsFirstResponder: Bool { true }
  }

  /// Catches a Cmd-Z that undoes a pane close while a text control is being edited. A pane is
  /// hidden. With a text field being edited, the standard undo action leaves the pane hidden and
  /// the menu item follows the edit's undo state. With a plain view focused, as a terminal is, the
  /// same action brings the pane back and the item reads Undo Close Pane.
  func testCommandZUndoesAnEditInATextControlAndAPaneCloseElsewhere() throws {
    let fixture = try makeFixture()
    let window = try XCTUnwrap(fixture.controller.window as? MainWindow)
    window.orderFrontRegardless()
    fixture.openPanes(2)
    fixture.controller.closePane(nil)

    let field = NSTextField(string: "abc")
    field.frame = NSRect(x: 0, y: 0, width: 100, height: 20)
    let plain = PlainView(frame: NSRect(x: 0, y: 30, width: 100, height: 20))
    window.contentView?.addSubview(field)
    window.contentView?.addSubview(plain)

    let item = NSMenuItem(
      title: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z")

    XCTAssertTrue(window.makeFirstResponder(field))
    XCTAssertTrue(window.firstResponder is NSText)
    XCTAssertFalse(window.validateMenuItem(item), "nothing typed, so the edit has no undo")

    window.undoCloseOrEdit(nil)

    XCTAssertEqual(fixture.controller.paneIDs, [id(1)], "Cmd-Z in a text field undid a close")
    XCTAssertEqual(fixture.controller.ledger.hidden.count, 1)

    XCTAssertTrue(window.makeFirstResponder(plain))
    XCTAssertTrue(window.validateMenuItem(item))
    XCTAssertEqual(item.title, "Undo Close Pane")

    window.undoCloseOrEdit(nil)

    XCTAssertEqual(fixture.controller.paneIDs, [id(1), id(2)])
  }
}

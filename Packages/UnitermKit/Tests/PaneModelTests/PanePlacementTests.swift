import CoreGraphics
import XCTest

@testable import PaneModel

/// Every expected number in this file was worked out by hand from the weights and the sizes in
/// the test, never read back from the code under test.
final class PanePlacementTests: XCTestCase {
  private let flat = PaneMetrics(
    minimumPaneSize: CGSize(width: 100, height: 50), dividerThickness: 0)

  private let wide = CGSize(width: 1000, height: 600)

  private func id(_ value: UInt64) -> NodeID { NodeID(rawValue: value) }

  private func rootSplit(_ tree: PaneTree) throws -> Split {
    guard case .split(let split) = tree.root else {
      throw XCTSkip("the root is a pane")
    }

    return split
  }

  /// Panes 1, 2, and 4 in a row with weights 0.5, 0.25, and 0.25. The split is 3.
  private func threeInARow() throws -> PaneTree {
    var tree = PaneTree(metrics: flat)
    try tree.split(id(1), axis: .row, in: wide)
    try tree.split(id(2), axis: .row, in: wide)
    return tree
  }

  /// Catches a placement that names the wrong neighbor or loses the weight. Pane 2 is in the middle
  /// of 1 and 4, so its previous sibling 1 is the neighbor, on the after side, with weight 0.25.
  func testAMiddlePaneRecordsItsPreviousSiblingAndItsWeight() throws {
    let tree = try threeInARow()

    XCTAssertEqual(
      tree.placement(of: id(2)),
      PanePlacement(neighbor: id(1), axis: .row, side: .after, weight: 0.25))
  }

  /// Catches a first pane that records no neighbor. Pane 1 has no previous sibling, so its next
  /// sibling 2 is the neighbor, on the before side.
  func testTheFirstPaneRecordsItsNextSibling() throws {
    let tree = try threeInARow()

    XCTAssertEqual(
      tree.placement(of: id(1)),
      PanePlacement(neighbor: id(2), axis: .row, side: .before, weight: 0.5))
  }

  /// Catches a lone pane that claims a place to return to. The only pane is not in any split.
  func testTheOnlyPaneHasNoPlacement() {
    let tree = PaneTree(metrics: flat)

    XCTAssertNil(tree.placement(of: id(1)))
  }

  /// Catches an undo that puts the pane in the wrong place or at the wrong size. Pane 2 closes and a
  /// new pane takes its place. It sits between 1 and 4 again, with ID 5. Closing gave 1 and 4
  /// weights 0.625 and 0.375. Returning takes 0.25 and scales them by 0.75: 0.46875 and 0.28125.
  func testAReopenedPaneTakesItsFormerPlaceAndWeight() throws {
    var tree = try threeInARow()
    let placement = try XCTUnwrap(tree.placement(of: id(2)))
    _ = try tree.close(id(2))

    let reopened = try tree.insert(at: placement, in: wide)

    XCTAssertEqual(reopened, id(5))
    let root = try rootSplit(tree)
    XCTAssertEqual(root.children.map { $0.node.id }, [id(1), id(5), id(4)])
    XCTAssertEqual(root.children.map(\.weight), [0.46875, 0.25, 0.28125])
  }

  /// Catches a pane reopened from a description that takes the old ID. The ID 4 is the next after
  /// the highest issued, 3, and it sits where 2 was.
  func testAReopenedPaneGetsANewID() throws {
    var tree = PaneTree(metrics: flat)
    try tree.split(id(1), axis: .row, in: wide)
    let placement = try XCTUnwrap(tree.placement(of: id(2)))
    _ = try tree.close(id(2))

    let reopened = try tree.insert(at: placement, in: wide)

    XCTAssertEqual(reopened, id(4))
    XCTAssertEqual(tree.paneIDs, [id(1), id(4)])
    XCTAssertFalse(tree.contains(id(2)))
  }

  /// Catches an undo of the only split that cannot rebuild it. Closing pane 2 leaves pane 1 alone.
  /// The neighbor is the root pane, so it is wrapped in a new split. The old split 3 stays retired.
  /// The new pane is 4 and the new split is 5. Both halves are 0.5.
  func testUndoingTheOnlySplitWrapsTheRootPane() throws {
    var tree = PaneTree(metrics: flat)
    try tree.split(id(1), axis: .row, in: wide)
    let placement = try XCTUnwrap(tree.placement(of: id(2)))
    _ = try tree.close(id(2))

    try tree.insert(at: placement, in: wide)

    let root = try rootSplit(tree)
    XCTAssertEqual(root.id, id(5))
    XCTAssertEqual(root.axis, .row)
    XCTAssertEqual(root.children.map { $0.node.id }, [id(1), id(4)])
    XCTAssertEqual(root.children.map(\.weight), [0.5, 0.5])
  }

  /// Catches an undo that ignores the placement's axis when the neighbor has since moved into a
  /// split of the other axis. Pane 1 was split along a column after pane 2 closed. Pane 2 returns
  /// beside pane 1 along the row, so pane 1 and the new pane 6 share a new row split inside the
  /// column.
  func testAChangedNeighborIsWrappedAlongTheRecordedAxis() throws {
    var tree = PaneTree(metrics: flat)
    try tree.split(id(1), axis: .row, in: wide)
    let placement = try XCTUnwrap(tree.placement(of: id(2)))
    _ = try tree.close(id(2))
    let below = try tree.split(id(1), axis: .column, in: wide)

    try tree.insert(at: placement, in: wide)

    let column = try rootSplit(tree)
    XCTAssertEqual(column.axis, .column)
    XCTAssertEqual(column.children.count, 2)
    XCTAssertEqual(column.children[1].node.id, below)

    guard case .split(let row) = column.children[0].node else {
      return XCTFail("pane 1 was not wrapped")
    }

    XCTAssertEqual(row.axis, .row)
    XCTAssertEqual(row.children.map { $0.node.id }, [id(1), id(6)])
    XCTAssertEqual(column.children[0].weight, 0.5)
  }

  /// Catches a neighbor that must be a pane. Pane 1 sat before a column split. Closing it leaves the
  /// column as the root. Undo places the new pane 6 beside that split by the split's own ID, 5.
  func testASplitCanBeTheNeighbor() throws {
    var tree = PaneTree(metrics: flat)
    try tree.split(id(1), axis: .row, in: wide)
    try tree.split(id(2), axis: .column, in: wide)
    let placement = try XCTUnwrap(tree.placement(of: id(1)))
    XCTAssertEqual(placement.neighbor, id(5))
    XCTAssertEqual(placement.side, .before)
    _ = try tree.close(id(1))

    try tree.insert(at: placement, in: wide)

    let root = try rootSplit(tree)
    XCTAssertEqual(root.axis, .row)
    XCTAssertEqual(root.children.map { $0.node.id }, [id(6), id(5)])
    XCTAssertEqual(root.children.map(\.weight), [0.5, 0.5])
  }

  /// Catches the fallback that is not defined. Panes 1, 2, 4, and 5 have weights 0.5, 0.25, 0.125,
  /// and 0.125. Pane 5 closes, then 4, so 5's neighbor is gone and the row holds 1 and 2 at 0.5
  /// each. The new pane 6 goes to the end of the root along the row with pane 5's recorded 0.125.
  /// The others scale by 0.875 to 0.4375 each.
  func testAGoneNeighborFallsBackToTheEndOfTheRoot() throws {
    var tree = PaneTree(metrics: flat)
    try tree.split(id(1), axis: .row, in: wide)
    try tree.split(id(2), axis: .row, in: wide)
    let fourth = try tree.split(id(4), axis: .row, in: wide)
    XCTAssertEqual(fourth, id(5))

    let placement = try XCTUnwrap(tree.placement(of: id(5)))
    XCTAssertEqual(placement.neighbor, id(4))
    _ = try tree.close(id(5))
    _ = try tree.close(id(4))

    try tree.insert(at: placement, in: wide)

    let root = try rootSplit(tree)
    XCTAssertEqual(root.children.map { $0.node.id }, [id(1), id(2), id(6)])
    XCTAssertEqual(root.children.map(\.weight), [0.4375, 0.4375, 0.125])
  }

  /// Catches a fallback that ignores the recorded side. Pane 1 sat before pane 2. With 2 and 1
  /// gone, only pane 4 is left. The new pane 5 goes before it, not after.
  func testTheFallbackKeepsTheRecordedSide() throws {
    var tree = try threeInARow()
    let placement = try XCTUnwrap(tree.placement(of: id(1)))
    XCTAssertEqual(placement.neighbor, id(2))
    _ = try tree.close(id(1))
    _ = try tree.close(id(2))
    XCTAssertEqual(tree.paneIDs, [id(4)])

    try tree.insert(at: placement, in: wide)

    XCTAssertEqual(tree.paneIDs, [id(5), id(4)])
    XCTAssertEqual(try rootSplit(tree).children.map(\.weight), [0.5, 0.5])
  }

  /// Catches an undo that squeezes a pane below its minimum. At 150 wide, two panes cannot both
  /// hold 100. The insert is refused, nothing changes, and no ID is used.
  func testAnInsertThatDoesNotFitIsRefusedAndUsesNoID() throws {
    var tree = PaneTree(metrics: flat)
    let tiny = CGSize(width: 150, height: 600)
    let placement = PanePlacement(neighbor: id(1), axis: .row, side: .after, weight: 0.5)
    let before = tree

    XCTAssertThrowsError(try tree.insert(at: placement, in: tiny)) { error in
      XCTAssertEqual(error as? PaneTreeError, .belowMinimumSize(id(1)))
    }

    XCTAssertEqual(tree, before)
    XCTAssertEqual(tree.highWaterMark, 1)
  }

  /// Catches a recorded weight that is applied even when it squeezes the pane. A recorded weight
  /// of 0.05 would leave the new pane 50 wide in 1000, below 100. An equal share fits, so each
  /// pane gets 0.5.
  func testAWeightThatDoesNotFitFallsBackToAnEqualShare() throws {
    var tree = PaneTree(metrics: flat)
    let placement = PanePlacement(neighbor: id(1), axis: .row, side: .after, weight: 0.05)

    try tree.insert(at: placement, in: wide)

    XCTAssertEqual(try rootSplit(tree).children.map(\.weight), [0.5, 0.5])
  }

  /// Catches an ID that comes back. A closed pane's ID is retired the moment the pane leaves the
  /// tree. A pane opened at its place gets a fresh ID, and the closed ID stays retired.
  func testAClosedPanesIDIsRetiredAndNeverIssuedAgain() throws {
    var tree = try threeInARow()
    let placement = try XCTUnwrap(tree.placement(of: id(2)))
    _ = try tree.close(id(2))

    XCTAssertTrue(tree.isRetired(id(2)))

    let fresh = try tree.insert(at: placement, in: wide)

    XCTAssertEqual(fresh, id(5))
    XCTAssertFalse(tree.paneIDs.contains(id(2)))
    XCTAssertTrue(tree.isRetired(id(2)))
  }

  /// Catches a node that vanished in a collapse and is issued again. Splitting 2 downward makes
  /// pane 4 and split 5, and closing pane 4 collapses split 5. Both are retired, and a pane opened
  /// afterward is 6.
  func testACollapsedNodeIDIsRetiredAndNeverIssuedAgain() throws {
    var tree = PaneTree(metrics: flat)
    try tree.split(id(1), axis: .row, in: wide)
    let lower = try tree.split(id(2), axis: .column, in: wide)
    let placement = try XCTUnwrap(tree.placement(of: id(1)))
    _ = try tree.close(lower)
    let collapsed = id(lower.rawValue + 1)

    XCTAssertFalse(tree.contains(collapsed))
    XCTAssertTrue(tree.isRetired(collapsed))

    let fresh = try tree.insert(at: placement, in: wide)

    XCTAssertEqual(fresh, id(6))
    XCTAssertTrue(tree.isRetired(collapsed))
  }

  /// Catches a pane that comes back as an extra nesting level. After the merge the tree never nests
  /// the same axis, so panes 1, 2, and 4 are still one row.
  func testAReturnedPaneNeverNestsTheSameAxis() throws {
    var tree = try threeInARow()
    let placement = try XCTUnwrap(tree.placement(of: id(4)))
    _ = try tree.close(id(4))

    try tree.insert(at: placement, in: wide)

    let root = try rootSplit(tree)
    XCTAssertEqual(root.children.count, 3)
    XCTAssertTrue(
      root.children.allSatisfy {
        if case .pane = $0.node { return true }
        return false
      })
  }
}

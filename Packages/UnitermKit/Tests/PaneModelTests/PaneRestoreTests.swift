import CoreGraphics
import XCTest

@testable import PaneModel

/// Every expected number was worked out by hand from the saved IDs and weights in the test.
final class PaneRestoreTests: XCTestCase {
  private let flat = PaneMetrics(
    minimumPaneSize: CGSize(width: 100, height: 50), dividerThickness: 0)

  private let wide = CGSize(width: 1000, height: 600)

  private func id(_ value: UInt64) -> NodeID { NodeID(rawValue: value) }

  private func pane(_ value: UInt64) -> Node { .pane(Pane(id: id(value))) }

  private func row(_ splitID: UInt64, _ children: [(Node, Double)]) -> Node {
    .split(
      Split(
        id: id(splitID), axis: .row,
        children: children.map { Child(node: $0.0, weight: $0.1) }))
  }

  /// Catches a restore that rebuilds the tree with different IDs or weights.
  func testARestoredTreeKeepsItsShapeAndIDs() throws {
    let root = row(5, [(pane(1), 0.25), (pane(2), 0.75)])
    let tree = try PaneTree(restoring: root, highWaterMark: 5, metrics: flat)

    XCTAssertEqual(tree.paneIDs, [id(1), id(2)])
    XCTAssertEqual(tree.root, root)

    let frames = tree.layout(in: wide).frames
    XCTAssertEqual(frames[id(1)]?.width, 250)
    XCTAssertEqual(frames[id(2)]?.width, 750)
  }

  /// Catches an allocator that restarts from the tree's own largest ID. The tree holds IDs 1 and
  /// 2 and a split 5, and the saved mark is 9, since IDs up to 9 were handed out and closed. The
  /// next split must use 10 for the pane and 11 for the split.
  func testNewIDsStartAboveTheSavedMark() throws {
    var tree = try PaneTree(
      restoring: row(5, [(pane(1), 0.5), (pane(2), 0.5)]), highWaterMark: 9, metrics: flat)

    let created = try tree.split(id(2), axis: .column, in: wide)

    XCTAssertEqual(created, id(10))
    XCTAssertEqual(tree.highWaterMark, 11)
  }

  /// A mark lower than the tree's own largest ID cannot be trusted. The allocator starts above
  /// the largest ID in the tree instead, so a new node never collides with a restored one.
  func testAMarkBelowTheLargestIDIsRaised() throws {
    var tree = try PaneTree(
      restoring: row(5, [(pane(1), 0.5), (pane(2), 0.5)]), highWaterMark: 0, metrics: flat)

    XCTAssertEqual(tree.highWaterMark, 5)
    XCTAssertEqual(try tree.split(id(1), axis: .column, in: wide), id(6))
  }

  /// Catches a restore that reissues the ID of a pane closed before the quit, whether it was
  /// parked for undo or gone. IDs 3 and 4 were handed out and are not in the tree. Both are
  /// retired, and a hidden pane's ID cannot be inserted from the new tree.
  func testIDsRetiredBeforeTheQuitStayRetired() throws {
    var tree = try PaneTree(
      restoring: row(5, [(pane(1), 0.5), (pane(2), 0.5)]), highWaterMark: 9, metrics: flat)

    for retired in [3, 4, 9] as [UInt64] {
      XCTAssertTrue(tree.isRetired(id(retired)), "\(retired)")
    }

    XCTAssertFalse(tree.isRetired(id(1)))

    let placement = PanePlacement(neighbor: id(1), axis: .row, side: .after, weight: 0.5)

    XCTAssertThrowsError(try tree.insert(id(3), at: placement, in: wide)) {
      XCTAssertEqual($0 as? PaneTreeError, .retired(id(3)))
    }

    XCTAssertThrowsError(try tree.insert(id(30), at: placement, in: wide)) {
      XCTAssertEqual($0 as? PaneTreeError, .neverIssued(id(30)))
    }
  }

  /// Catches an allocator that traps on overflow. A mark of the largest integer would crash the
  /// next split. The mark is lowered, so a split still gets an ID.
  func testAnImplausibleMarkNeverTrapsTheAllocator() throws {
    var tree = try PaneTree(
      restoring: row(5, [(pane(1), 0.5), (pane(2), 0.5)]), highWaterMark: UInt64.max, metrics: flat)

    XCTAssertEqual(tree.highWaterMark, NodeIDAllocator.maximumMark)

    let created = try tree.split(id(1), axis: .column, in: wide)

    XCTAssertEqual(created.rawValue, NodeIDAllocator.maximumMark + 1)
  }

  func testARepeatedOrZeroIDIsRefused() {
    XCTAssertThrowsError(
      try PaneTree(
        restoring: row(5, [(pane(1), 0.5), (pane(1), 0.5)]), highWaterMark: 5, metrics: flat)
    ) {
      guard case .invalidRestore? = $0 as? PaneTreeError else {
        return XCTFail("expected invalidRestore, got \($0)")
      }
    }

    XCTAssertThrowsError(try PaneTree(restoring: pane(0), highWaterMark: 5, metrics: flat))
  }

  /// A hand-edited file can hold a split with one child, or a split inside a split of the same
  /// axis. Restore normalizes them like any other edit, so the layout matches what the user sees.
  func testARestoredTreeIsNormalized() throws {
    let inner = row(6, [(pane(2), 0.5), (pane(3), 0.5)])
    let root = row(5, [(pane(1), 0.5), (inner, 0.5)])

    let tree = try PaneTree(restoring: root, highWaterMark: 6, metrics: flat)

    XCTAssertEqual(
      tree.root, row(5, [(pane(1), 0.5), (pane(2), 0.25), (pane(3), 0.25)]))
  }
}

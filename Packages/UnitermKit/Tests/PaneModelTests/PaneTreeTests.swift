import CoreGraphics
import XCTest

@testable import PaneModel

/// Every expected number in this file was worked out by hand from the weights and the sizes in
/// the test, never read back from the code under test.
final class PaneTreeTests: XCTestCase {
  /// Dividers take no room, so sizes are plain weight times length.
  private let flat = PaneMetrics(
    minimumPaneSize: CGSize(width: 100, height: 50), dividerThickness: 0)

  /// Dividers are 10 points thick.
  private let spaced = PaneMetrics(
    minimumPaneSize: CGSize(width: 100, height: 50), dividerThickness: 10)

  private let wide = CGSize(width: 1000, height: 600)

  private func id(_ value: UInt64) -> NodeID { NodeID(rawValue: value) }

  private func weights(_ split: Split) -> [Double] { split.children.map(\.weight) }

  private func children(_ tree: PaneTree) -> [Child] {
    guard case .split(let split) = tree.root else { return [] }
    return split.children
  }

  // MARK: Splitting

  /// Catches a split that is not a split: two panes must share the width evenly, with the divider
  /// between them. 1000 wide with a 10 divider leaves 990, so 495 each.
  func testSplitOfTheOnlyPaneMakesTwoEqualSiblings() throws {
    var tree = PaneTree(metrics: spaced)

    let created = try tree.split(id(1), axis: .row, in: wide)

    XCTAssertEqual(created, id(2))
    XCTAssertEqual(tree.paneIDs, [id(1), id(2)])

    let layout = tree.layout(in: wide)
    XCTAssertEqual(layout.frames[id(1)], CGRect(x: 0, y: 0, width: 495, height: 600))
    XCTAssertEqual(layout.frames[id(2)], CGRect(x: 505, y: 0, width: 495, height: 600))
    XCTAssertEqual(layout.dividers.map(\.frame), [CGRect(x: 495, y: 0, width: 10, height: 600)])
  }

  /// Catches a same-axis split that nests a new split inside the old one. Splitting pane 2 along
  /// the row inserts a sibling, so the root keeps three children: 0.5, 0.25, 0.25. Two dividers
  /// leave 980, so the widths are 490, 245, and 245.
  func testSplitAlongTheParentsAxisInsertsASibling() throws {
    var tree = PaneTree(metrics: spaced)
    try tree.split(id(1), axis: .row, in: wide)

    let created = try tree.split(id(2), axis: .row, in: wide)

    guard case .split(let root) = tree.root else { return XCTFail("root is a pane") }
    XCTAssertEqual(root.id, id(3))
    XCTAssertEqual(root.children.map { $0.node.id }, [id(1), id(2), created])
    XCTAssertEqual(weights(root), [0.5, 0.25, 0.25])

    let layout = tree.layout(in: wide)
    XCTAssertEqual(layout.frames[id(1)]?.width, 490)
    XCTAssertEqual(layout.frames[id(2)], CGRect(x: 500, y: 0, width: 245, height: 600))
    XCTAssertEqual(layout.frames[created], CGRect(x: 755, y: 0, width: 245, height: 600))
  }

  /// Catches a cross-axis split that is flattened into the parent. Pane 2 split along the column
  /// becomes a column inside the row. With a 10 divider, 600 high leaves 590, so 295 each.
  func testSplitAcrossTheParentsAxisNestsASplit() throws {
    var tree = PaneTree(metrics: spaced)
    try tree.split(id(1), axis: .row, in: wide)

    let created = try tree.split(id(2), axis: .column, in: wide)

    guard case .split(let root) = tree.root, case .split(let inner) = root.children[1].node else {
      return XCTFail("expected a nested column")
    }
    XCTAssertEqual(inner.axis, .column)
    XCTAssertEqual(inner.children.map { $0.node.id }, [id(2), created])
    XCTAssertEqual(weights(root), [0.5, 0.5])

    let layout = tree.layout(in: wide)
    XCTAssertEqual(layout.frames[id(2)], CGRect(x: 505, y: 0, width: 495, height: 295))
    XCTAssertEqual(layout.frames[created], CGRect(x: 505, y: 305, width: 495, height: 295))
  }

  // MARK: Minimum size

  /// Catches a split that ignores the minimum. At 1000 wide with no divider, repeated splits of
  /// pane 1 give it 500, 250, then 125. A fourth would leave 62.5 and 62.5, below 100, so it is
  /// refused. The refusal changes nothing and uses no ID.
  func testSplitBelowTheMinimumIsRefusedAndChangesNothing() throws {
    var tree = PaneTree(metrics: flat)
    try tree.split(id(1), axis: .row, in: wide)
    try tree.split(id(1), axis: .row, in: wide)
    try tree.split(id(1), axis: .row, in: wide)

    let before = tree
    XCTAssertEqual(tree.layout(in: wide).frames[id(1)]?.width, 125)

    XCTAssertThrowsError(try tree.split(id(1), axis: .row, in: wide)) {
      XCTAssertEqual($0 as? PaneTreeError, .belowMinimumSize(id(1)))
    }

    XCTAssertEqual(tree, before)
    XCTAssertEqual(tree.highWaterMark, before.highWaterMark)
    XCTAssertFalse(tree.canSplit(id(1), axis: .row, in: wide))
    XCTAssertTrue(tree.canSplit(id(1), axis: .column, in: wide))
  }

  /// Catches a height check that is missing. At 150 high with a minimum of 50, one column split
  /// gives 75 each. Splitting either half again would leave 37.5, below 50, so it is refused.
  func testTheMinimumHeightRefusesAColumnSplit() throws {
    var tree = PaneTree(metrics: flat)
    let size = CGSize(width: 1000, height: 150)

    try tree.split(id(1), axis: .column, in: size)
    XCTAssertEqual(tree.layout(in: size).frames[id(1)]?.height, 75)

    XCTAssertThrowsError(try tree.split(id(1), axis: .column, in: size))
    XCTAssertThrowsError(try tree.split(id(2), axis: .column, in: size))
  }

  /// Catches a minimum size that ignores nesting. Row [1, column [2, 3]] with a 10 divider needs
  /// 100 + 10 + 100 = 210 wide, and max(50, 50 + 10 + 50) = 110 high.
  func testMinimumSizeFollowsTheTree() throws {
    var tree = PaneTree(metrics: spaced)
    XCTAssertEqual(tree.minimumSize, CGSize(width: 100, height: 50))

    try tree.split(id(1), axis: .row, in: wide)
    XCTAssertEqual(tree.minimumSize, CGSize(width: 210, height: 50))

    try tree.split(id(2), axis: .column, in: wide)
    XCTAssertEqual(tree.minimumSize, CGSize(width: 210, height: 110))
  }

  /// Catches a layout that shrinks a pane below its minimum. Weights 0.1 and 0.9 at 400 wide give
  /// 40 and 360, so pane 1 is held at 100 and pane 2 takes the other 300.
  func testLayoutHoldsAPaneAtItsMinimum() throws {
    var tree = PaneTree(metrics: flat)
    try tree.split(id(1), axis: .row, in: wide)
    try tree.moveDivider(between: id(1), and: id(2), by: -400, in: wide)

    guard case .split(let root) = tree.root else { return XCTFail("root is a pane") }
    XCTAssertEqual(weights(root)[0], 0.1, accuracy: 1e-12)
    XCTAssertEqual(weights(root)[1], 0.9, accuracy: 1e-12)

    let small = CGSize(width: 400, height: 300)
    let frames = tree.layout(in: small).frames
    XCTAssertEqual(frames[id(1)]?.width, 100)
    XCTAssertEqual(frames[id(2)]?.width, 300)
    XCTAssertEqual(frames[id(2)]?.minX, 100)

    let tiny = tree.layout(in: CGSize(width: 150, height: 300)).frames
    XCTAssertEqual(tiny[id(1)]?.width, 100)
    XCTAssertEqual(tiny[id(2)]?.width, 100)
  }

  // MARK: Close

  /// Catches a close that gives all its space to one side. Weights 0.5, 0.25, 0.25: closing the
  /// middle pane gives half of 0.25 to each neighbor, so 0.625 and 0.375.
  func testClosingAMiddlePaneSplitsItsSpaceBetweenBothNeighbors() throws {
    var tree = PaneTree(metrics: flat)
    try tree.split(id(1), axis: .row, in: wide)
    try tree.split(id(2), axis: .row, in: wide)

    let outcome = try tree.close(id(2))

    XCTAssertEqual(outcome, .closed(focus: id(1)))
    XCTAssertEqual(children(tree).map { $0.node.id }, [id(1), id(4)])
    XCTAssertEqual(children(tree).map(\.weight), [0.625, 0.375])
  }

  /// Catches an end pane that leaves its space unclaimed. Closing the first of 0.25, 0.25, 0.5
  /// gives all 0.25 to the one neighbor: 0.5, 0.5.
  func testClosingAnEndPaneGivesAllItsSpaceToTheOnlyNeighbor() throws {
    var tree = PaneTree(metrics: flat)
    try tree.split(id(1), axis: .row, in: wide)
    try tree.split(id(1), axis: .row, in: wide)

    XCTAssertEqual(children(tree).map(\.weight), [0.25, 0.25, 0.5])

    let outcome = try tree.close(id(1))

    XCTAssertEqual(outcome, .closed(focus: id(4)))
    XCTAssertEqual(children(tree).map(\.weight), [0.5, 0.5])
  }

  /// Catches a split left with one child. Closing pane 2 of two leaves pane 1 as the root. The
  /// split's ID is retired, and pane 1 keeps its own.
  func testClosingTheSecondOfTwoPanesCollapsesTheSplit() throws {
    var tree = PaneTree(metrics: flat)
    try tree.split(id(1), axis: .row, in: wide)

    let outcome = try tree.close(id(2))

    XCTAssertEqual(outcome, .closed(focus: id(1)))
    XCTAssertEqual(tree.root, .pane(Pane(id: id(1))))
    XCTAssertTrue(tree.isRetired(id(3)))
    XCTAssertTrue(tree.isRetired(id(2)))
    XCTAssertFalse(tree.isRetired(id(1)))
  }

  /// Catches a close of the last pane that empties the tree.
  func testClosingTheLastPaneChangesNothingAndSaysSo() throws {
    var tree = PaneTree(metrics: flat)

    XCTAssertEqual(try tree.close(id(1)), .lastPane)
    XCTAssertEqual(tree.paneIDs, [id(1)])
  }

  func testClosingAnUnknownPaneThrows() {
    var tree = PaneTree(metrics: flat)

    XCTAssertThrowsError(try tree.close(id(9))) {
      XCTAssertEqual($0 as? PaneTreeError, .unknownPane(id(9)))
    }
  }

  // MARK: Merge

  /// Catches a merge that forgets to scale the weights by the merged split's weight.
  ///
  /// Row 3 holds pane 1 and column 5, each at 0.5. Column 5 holds pane 2 and row 7, each at 0.5,
  /// and row 7 holds panes 4 and 6 at 0.5 each. Closing pane 2 leaves column 5 with only row 7,
  /// which collapses into column 5's place, and then merges into row 3. Row 7's children carry
  /// 0.5 * 0.5 = 0.25 each, beside pane 1's 0.5. At 1200 wide with no dividers, panes 4 and 6 stay
  /// 300 wide, as they were inside row 7.
  func testMergeScalesWeightsSoNoPaneChangesWidth() throws {
    let size = CGSize(width: 1200, height: 600)
    var tree = PaneTree(metrics: flat)
    try tree.split(id(1), axis: .row, in: size)
    try tree.split(id(2), axis: .column, in: size)
    try tree.split(id(4), axis: .row, in: size)

    let before = tree.layout(in: size).frames
    XCTAssertEqual(before[id(4)]?.width, 300)
    XCTAssertEqual(before[id(6)]?.width, 300)

    let outcome = try tree.close(id(2))

    XCTAssertEqual(outcome, .closed(focus: id(4)))

    guard case .split(let root) = tree.root else { return XCTFail("root is a pane") }
    XCTAssertEqual(root.id, id(3))
    XCTAssertEqual(root.children.map { $0.node.id }, [id(1), id(4), id(6)])
    XCTAssertEqual(weights(root), [0.5, 0.25, 0.25])

    let after = tree.layout(in: size).frames
    XCTAssertEqual(after[id(1)]?.width, 600)
    XCTAssertEqual(after[id(4)]?.width, 300)
    XCTAssertEqual(after[id(6)]?.width, 300)
    XCTAssertEqual(after[id(4)]?.height, 600)

    XCTAssertTrue(tree.isRetired(id(5)))
    XCTAssertTrue(tree.isRetired(id(7)))
  }

  /// Catches a merge bound that is too tight for a split with three children, and a merge that
  /// moves panes by some other amount than the divider arithmetic says.
  ///
  /// Dividers are 10 thick. At 1000 wide, row 3 holds pane 1 and column 5 at 0.5 each. Column 5
  /// holds pane 2 and row 7 at 0.5 each, and row 7 holds panes 4, 6, and 8 at 0.5, 0.25, 0.25.
  /// Row 3 has one divider, so its panes share 990 and column 5 is 495 wide. Row 7 has two
  /// dividers, so its panes share 495 - 20 = 475: panes 4, 6, and 8 are 237.5, 118.75, and 118.75
  /// wide. Closing pane 2 merges row 7 into row 3 at weight 0.5. Row 3 then has four children and
  /// three dividers, so its panes share 1000 - 30 = 970. Pane 4 is 0.25 * 970 = 242.5 wide, and
  /// panes 6 and 8 are 0.125 * 970 = 121.25. Pane 1 is 485 wide. The shifts are 5, 2.5, and 2.5.
  /// The formula c * (m - 1) * (1 - w) * d gives 0.5 * 2 * 0.5 * 10 = 5 and 0.25 * 2 * 0.5 * 10 =
  /// 2.5. A pane can shift by up to (m - 1) * d, here 20, so a bound of one divider is wrong.
  func testMergeShiftsPanesByTheDividerArithmetic() throws {
    let size = CGSize(width: 1000, height: 1200)
    var tree = PaneTree(metrics: spaced)
    try tree.split(id(1), axis: .row, in: size)
    try tree.split(id(2), axis: .column, in: size)
    try tree.split(id(4), axis: .row, in: size)
    try tree.split(id(6), axis: .row, in: size)

    let before = tree.layout(in: size).frames
    XCTAssertEqual(before[id(4)]?.width ?? 0, 237.5, accuracy: 1e-9)
    XCTAssertEqual(before[id(6)]?.width ?? 0, 118.75, accuracy: 1e-9)
    XCTAssertEqual(before[id(8)]?.width ?? 0, 118.75, accuracy: 1e-9)

    _ = try tree.close(id(2))

    let after = tree.layout(in: size).frames
    XCTAssertEqual(after[id(1)]?.width ?? 0, 485, accuracy: 1e-9)
    XCTAssertEqual(after[id(4)]?.width ?? 0, 242.5, accuracy: 1e-9)
    XCTAssertEqual(after[id(6)]?.width ?? 0, 121.25, accuracy: 1e-9)
    XCTAssertEqual(after[id(8)]?.width ?? 0, 121.25, accuracy: 1e-9)
  }

  /// Catches a split that fits its own two panes and squeezes the rest out of the window.
  ///
  /// Dividers take no room and panes need 100 wide. A row of panes 1, 2, and 4 is dragged to
  /// weights 0.6, 0.2, and 0.2. In 350 points that is 210, 70, and 70. Panes 2 and 4 are held at
  /// 100, so pane 1 shows 150. Splitting pane 1 would give it and the new pane 0.3 each, 105
  /// points, which passes a check of those two. But four panes need 400 points and the window has
  /// 350, so the layout would hold panes 2 and 4 at 100 and leave the other two 75 each.
  func testSplitThatSqueezesOtherPanesBelowTheMinimumIsRefused() throws {
    let wideBuild = CGSize(width: 1000, height: 300)
    var tree = PaneTree(metrics: flat)
    try tree.split(id(1), axis: .row, in: wideBuild)
    try tree.split(id(2), axis: .row, in: wideBuild)
    try tree.moveDivider(between: id(2), and: id(4), by: 50, in: wideBuild)
    try tree.moveDivider(between: id(1), and: id(2), by: 100, in: wideBuild)

    let small = CGSize(width: 350, height: 300)
    let frames = tree.layout(in: small).frames
    XCTAssertEqual(frames[id(1)]?.width ?? 0, 150, accuracy: 1e-6)
    XCTAssertEqual(frames[id(2)]?.width ?? 0, 100, accuracy: 1e-6)

    let before = tree

    XCTAssertThrowsError(try tree.split(id(1), axis: .row, in: small)) {
      XCTAssertEqual($0 as? PaneTreeError, .belowMinimumSize(id(1)))
    }

    XCTAssertEqual(tree, before)
    XCTAssertFalse(tree.canSplit(id(1), axis: .row, in: small))
    XCTAssertTrue(tree.canSplit(id(1), axis: .row, in: CGSize(width: 400, height: 300)))
  }

  /// Catches a split rule that refuses too much. Dividers are 10 thick and panes need 100. A row
  /// of 520 holds panes 1, 2, and 4 at 300, 100, and 100, weights 0.6, 0.2, and 0.2. Splitting
  /// pane 1 adds a divider, so the weights give panes 2 and 4 98 each. The four panes need
  /// 4 * 100 + 30 = 430 and 520 is enough. So the split is allowed, the layout holds panes 2 and 4
  /// at 100, and the other two share 520 - 30 - 200 = 290, which is 145 each.
  func testSplitIsAllowedWhenTheLayoutCanHoldTheNeighborsAtTheirMinimum() throws {
    let build = CGSize(width: 520, height: 300)
    var tree = PaneTree(metrics: spaced)
    try tree.split(id(1), axis: .row, in: build)
    try tree.split(id(2), axis: .row, in: build)
    try tree.moveDivider(between: id(2), and: id(4), by: 25, in: build)
    try tree.moveDivider(between: id(1), and: id(2), by: 50, in: build)

    let created = try tree.split(id(1), axis: .row, in: build)

    let frames = tree.layout(in: build).frames
    XCTAssertEqual(frames[id(1)]?.width ?? 0, 145, accuracy: 1e-6)
    XCTAssertEqual(frames[created]?.width ?? 0, 145, accuracy: 1e-6)
    XCTAssertEqual(frames[id(2)]?.width ?? 0, 100, accuracy: 1e-6)
    XCTAssertEqual(frames[id(4)]?.width ?? 0, 100, accuracy: 1e-6)
  }

  /// Catches a collapse that lets the survivor keep an axis its parent already has. After the
  /// column collapses the tree must hold no split inside a split of the same axis.
  func testTheNormalizedTreeNeverNestsTheSameAxis() throws {
    var tree = PaneTree(metrics: flat)
    let size = CGSize(width: 2000, height: 1200)
    try tree.split(id(1), axis: .row, in: size)
    try tree.split(id(2), axis: .column, in: size)
    try tree.split(id(4), axis: .row, in: size)
    try tree.split(id(4), axis: .column, in: size)
    _ = try tree.close(id(2))
    _ = try tree.close(id(1))

    func check(_ node: Node, parent: Axis?) {
      guard case .split(let split) = node else { return }

      XCTAssertNotEqual(split.axis, parent)
      XCTAssertGreaterThan(split.children.count, 1)
      XCTAssertEqual(split.children.reduce(0) { $0 + $1.weight }, 1, accuracy: 1e-9)
      for child in split.children { check(child.node, parent: split.axis) }
    }

    check(tree.root, parent: nil)
  }

  // MARK: Divider

  /// Catches a drag that moves the wrong amount of space or touches a third child. Weights 0.5,
  /// 0.25, 0.25 at 1000 wide are 500, 250, 250. Dragging the first divider 100 right gives 600,
  /// 150, 250, so the weights are 0.6, 0.15, 0.25.
  func testDraggingMovesSpaceBetweenTheTwoAdjacentChildrenOnly() throws {
    var tree = PaneTree(metrics: flat)
    try tree.split(id(1), axis: .row, in: wide)
    try tree.split(id(2), axis: .row, in: wide)

    let moved = try tree.moveDivider(between: id(1), and: id(2), by: 100, in: wide)

    XCTAssertEqual(moved, 100)
    XCTAssertEqual(children(tree).map(\.weight)[0], 0.6, accuracy: 1e-12)
    XCTAssertEqual(children(tree).map(\.weight)[1], 0.15, accuracy: 1e-12)
    XCTAssertEqual(children(tree).map(\.weight)[2], 0.25, accuracy: 1e-12)

    let frames = tree.layout(in: wide).frames
    XCTAssertEqual(frames[id(1)]?.width ?? 0, 600, accuracy: 1e-9)
    XCTAssertEqual(frames[id(2)]?.width ?? 0, 150, accuracy: 1e-9)
    XCTAssertEqual(frames[id(4)]?.width ?? 0, 250, accuracy: 1e-9)
  }

  /// Catches a drag that crushes a pane. Pane 2 is 500 wide with a minimum of 100, so the divider
  /// stops 400 to the right, leaving widths 900 and 100.
  func testDraggingStopsAtTheMinimum() throws {
    var tree = PaneTree(metrics: flat)
    try tree.split(id(1), axis: .row, in: wide)

    let right = try tree.moveDivider(between: id(1), and: id(2), by: 700, in: wide)
    XCTAssertEqual(right, 400)
    XCTAssertEqual(tree.layout(in: wide).frames[id(2)]?.width ?? 0, 100, accuracy: 1e-9)

    let left = try tree.moveDivider(between: id(1), and: id(2), by: -2000, in: wide)
    XCTAssertEqual(left, -800)
    XCTAssertEqual(tree.layout(in: wide).frames[id(1)]?.width ?? 0, 100, accuracy: 1e-9)
  }

  /// Catches a drag that respects only the first pane inside the neighbor. The column beside pane
  /// 1 holds a row of two panes, so it needs 200 wide. Pane 1 starts at 500 of 1000, and the
  /// divider stops when pane 1 reaches 800, a move of 300.
  func testDraggingRespectsTheMinimumOfAWholeSubtree() throws {
    var tree = PaneTree(metrics: flat)
    try tree.split(id(1), axis: .row, in: wide)
    try tree.split(id(2), axis: .column, in: wide)
    try tree.split(id(4), axis: .row, in: wide)

    let split = tree.root
    guard case .split(let root) = split else { return XCTFail("root is a pane") }
    let column = root.children[1].node.id

    let moved = try tree.moveDivider(between: id(1), and: column, by: 900, in: wide)

    XCTAssertEqual(moved, 300)
    XCTAssertEqual(tree.layout(in: wide).frames[column]?.width ?? 0, 200, accuracy: 1e-9)
  }

  func testDraggingNonSiblingsThrows() throws {
    var tree = PaneTree(metrics: flat)
    try tree.split(id(1), axis: .row, in: wide)
    try tree.split(id(2), axis: .row, in: wide)

    XCTAssertThrowsError(try tree.moveDivider(between: id(1), and: id(4), by: 10, in: wide)) {
      XCTAssertEqual($0 as? PaneTreeError, .notAdjacent(id(1), id(4)))
    }
    XCTAssertThrowsError(try tree.moveDivider(between: id(2), and: id(1), by: 10, in: wide))
  }

  // MARK: IDs

  /// Catches an allocator that reuses an ID. Pane 2 closes and its split retires, then new nodes
  /// get IDs above everything handed out before.
  func testRetiredIDsAreNeverReused() throws {
    var tree = PaneTree(metrics: flat)
    try tree.split(id(1), axis: .row, in: wide)
    _ = try tree.close(id(2))

    XCTAssertEqual(tree.highWaterMark, 3)

    let created = try tree.split(id(1), axis: .row, in: wide)

    XCTAssertEqual(created, id(4))
    guard case .split(let root) = tree.root else { return XCTFail("root is a pane") }
    XCTAssertEqual(root.id, id(5))
    XCTAssertTrue(tree.isRetired(id(2)))
    XCTAssertTrue(tree.isRetired(id(3)))
  }

  /// Catches a refused split that burns IDs. The next split after a refusal gets the next ID in
  /// sequence.
  func testARefusedSplitUsesNoID() throws {
    let tiny = CGSize(width: 150, height: 600)
    var tree = PaneTree(metrics: flat)

    XCTAssertThrowsError(try tree.split(id(1), axis: .row, in: tiny))
    XCTAssertEqual(tree.highWaterMark, 1)

    XCTAssertEqual(try tree.split(id(1), axis: .column, in: tiny), id(2))
  }

  /// Catches a restored allocator that collides with saved IDs. A tree restored with high-water
  /// mark 41 starts its first pane at 42 and never issues 41 or lower.
  func testARestoredAllocatorStartsAboveItsHighWaterMark() throws {
    var tree = PaneTree(metrics: flat, allocator: NodeIDAllocator(highWaterMark: 41))

    XCTAssertEqual(tree.paneIDs, [id(42)])
    XCTAssertTrue(tree.isRetired(id(7)))
    XCTAssertEqual(try tree.split(id(42), axis: .row, in: wide), id(43))
    XCTAssertEqual(tree.highWaterMark, 44)
  }

  // MARK: Focus

  /// The tree is row [1, column [2, 4]] at 1000 by 600 with no dividers. Pane 1 is the left half,
  /// 2 is the top right quarter, and 4 is the bottom right.
  private func gridTree() throws -> PaneTree {
    var tree = PaneTree(metrics: flat)
    try tree.split(id(1), axis: .row, in: wide)
    try tree.split(id(2), axis: .column, in: wide)
    return tree
  }

  /// Catches a direction search that picks the wrong pane when two overlap equally. Pane 1 spans
  /// both right-hand panes by 300 each, so the tie goes to the upper one.
  func testNeighborsFollowGeometry() throws {
    let tree = try gridTree()

    XCTAssertEqual(tree.neighbor(of: id(1), toward: .right, in: wide), id(2))
    XCTAssertEqual(tree.neighbor(of: id(4), toward: .left, in: wide), id(1))
    XCTAssertEqual(tree.neighbor(of: id(2), toward: .left, in: wide), id(1))
    XCTAssertEqual(tree.neighbor(of: id(4), toward: .up, in: wide), id(2))
    XCTAssertEqual(tree.neighbor(of: id(2), toward: .down, in: wide), id(4))
  }

  /// Catches a direction search that wraps or reaches across a gap with no pane.
  func testNoNeighborPastAnEdge() throws {
    let tree = try gridTree()

    XCTAssertNil(tree.neighbor(of: id(1), toward: .left, in: wide))
    XCTAssertNil(tree.neighbor(of: id(1), toward: .up, in: wide))
    XCTAssertNil(tree.neighbor(of: id(2), toward: .up, in: wide))
    XCTAssertNil(tree.neighbor(of: id(4), toward: .down, in: wide))
    XCTAssertNil(tree.neighbor(of: id(2), toward: .right, in: wide))
    XCTAssertNil(tree.neighbor(of: id(1), toward: .down, in: wide))
  }

  /// Catches a next and previous order that is not reading order, or that stops at the ends.
  func testNextAndPreviousWrapInReadingOrder() throws {
    let tree = try gridTree()

    XCTAssertEqual(tree.nextPane(after: id(1)), id(2))
    XCTAssertEqual(tree.nextPane(after: id(2)), id(4))
    XCTAssertEqual(tree.nextPane(after: id(4)), id(1))
    XCTAssertEqual(tree.previousPane(before: id(1)), id(4))
    XCTAssertEqual(tree.previousPane(before: id(4)), id(2))
    XCTAssertNil(tree.nextPane(after: id(99)))
  }
}

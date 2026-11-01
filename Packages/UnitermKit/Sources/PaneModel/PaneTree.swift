import CoreGraphics
import Foundation

public enum PaneTreeError: Error, Equatable {
  case unknownPane(NodeID)

  /// The split would leave a pane smaller than the minimum. The pane named is the one that was
  /// split, or the new one when it is the one that is too small.
  case belowMinimumSize(NodeID)

  /// The two nodes are not neighbors under one split.
  case notAdjacent(NodeID, NodeID)

  /// The ID to bring back was never handed out by this tree.
  case neverIssued(NodeID)

  /// A saved tree cannot be restored: an ID is zero or repeats.
  case invalidRestore(String)

  /// The ID to bring back belongs to a node that is gone for good: it was retired, or it was never
  /// closed as a pane.
  case retired(NodeID)

  /// The pane to bring back is already in the tree.
  case alreadyInTree(NodeID)
}

/// Which side of its neighbor a pane sits on. `before` is left of it in a row and above it in a
/// column.
public enum Side: Sendable, Equatable {
  case before
  case after
}

/// Where a closed pane sat, kept by stable IDs so it survives changes to the tree.
///
/// The neighbor is the pane's previous sibling, or its next one when it was first. It can be a
/// split. The weight is the share the pane had of its parent split.
public struct PanePlacement: Sendable, Equatable {
  public let neighbor: NodeID
  public let axis: Axis
  public let side: Side
  public let weight: Double

  public init(neighbor: NodeID, axis: Axis, side: Side, weight: Double) {
    self.neighbor = neighbor
    self.axis = axis
    self.side = side
    self.weight = weight
  }
}

public enum CloseOutcome: Sendable, Equatable {
  /// The pane is gone. `focus` is the pane that took over its place.
  case closed(focus: NodeID)

  /// The pane is the only one, so nothing changed. The caller closes the window.
  case lastPane
}

/// The pane tree of one window: a normalized N-ary tree.
///
/// A split holds two or more children along one axis, each with a weight. A split left with one
/// child collapses. A child with its parent's axis merges into the parent. Behavior follows what
/// the user sees, never how the tree was built.
///
/// Nodes are addressed by ID. Nothing takes a path or a sibling index, since normalization
/// rewrites both.
public struct PaneTree: Sendable, Equatable {
  public private(set) var root: Node
  public let metrics: PaneMetrics
  private var allocator: NodeIDAllocator

  /// Panes closed with `close(_:)` whose IDs can still come back through `insert(_:at:in:)`. An ID
  /// leaves this set when the pane returns or when the caller retires it. A node that vanished in
  /// a collapse is never in it.
  private var parked: Set<NodeID> = []

  /// The largest ID ever handed out. A saved layout stores it.
  public var highWaterMark: UInt64 { allocator.highWaterMark }

  /// Makes a tree with one pane.
  public init(metrics: PaneMetrics = .standard, allocator: NodeIDAllocator = NodeIDAllocator()) {
    var allocator = allocator
    self.root = .pane(Pane(id: allocator.next()))
    self.metrics = metrics
    self.allocator = allocator
  }

  /// Makes a tree from a saved one. The allocator starts at `highWaterMark`, or at the largest ID in
  /// `root` when that is larger, so no ID that was handed out before the save is handed out again.
  /// That includes the IDs of panes that were closed and are not in `root`.
  ///
  /// The saved tree is normalized, since a file may have been edited. Throws when an ID is zero or
  /// repeats, because two nodes cannot share an identity.
  public init(
    restoring root: Node, highWaterMark: UInt64, metrics: PaneMetrics = .standard
  ) throws {
    var seen = Set<NodeID>()

    for id in root.allIDs {
      guard id.rawValue > 0 else { throw PaneTreeError.invalidRestore("a node has the ID 0") }

      guard seen.insert(id).inserted else {
        throw PaneTreeError.invalidRestore("the ID \(id) is used by two nodes")
      }
    }

    let highest = seen.map(\.rawValue).max() ?? 0

    self.root = root.normalizedRoot()
    self.metrics = metrics
    self.allocator = NodeIDAllocator(highWaterMark: max(highWaterMark, highest))
  }

  public var paneIDs: [NodeID] { root.paneIDs }

  public func contains(_ id: NodeID) -> Bool {
    root.contains(id)
  }

  /// True when the ID was handed out and its node is gone.
  public func isRetired(_ id: NodeID) -> Bool {
    id.rawValue <= allocator.highWaterMark && !root.contains(id)
  }

  /// The smallest size the whole tree can take without pushing a pane below its minimum.
  public var minimumSize: CGSize {
    root.minimumSize(metrics)
  }

  /// Where every node sits in `size`. When `size` is too small, the layout holds each pane at its
  /// minimum and overflows.
  public func layout(in size: CGSize) -> PaneLayout {
    layout(in: size, clamped: true)
  }

  private func layout(in size: CGSize, clamped: Bool, of node: Node? = nil) -> PaneLayout {
    var layout = PaneLayout()
    (node ?? root).place(
      in: CGRect(origin: .zero, size: size), metrics: metrics, clamped: clamped, into: &layout)
    return layout
  }

  // MARK: Split

  /// Splits a pane along `axis` and returns the new pane. The new pane sits after the old one, to
  /// its right or below it, and takes half of its space.
  ///
  /// The split is refused when either pane would end up below the minimum size. Nothing changes
  /// then, and no ID is used.
  @discardableResult
  public mutating func split(_ target: NodeID, axis: Axis, in size: CGSize) throws -> NodeID {
    guard root.paneIDs.contains(target) else { throw PaneTreeError.unknownPane(target) }

    var allocator = self.allocator
    let newPane = allocator.next()

    guard let inserted = root.splitting(target, axis: axis, newPane: newPane, allocator: &allocator)
    else { throw PaneTreeError.unknownPane(target) }

    let candidate = inserted.normalizedRoot()
    let ideal = layout(in: size, clamped: false, of: candidate)
    let minimum = metrics.minimumPaneSize

    for id in [target, newPane] {
      guard let frame = ideal.frames[id], frame.width >= minimum.width - Self.tolerance,
        frame.height >= minimum.height - Self.tolerance
      else { throw PaneTreeError.belowMinimumSize(id) }
    }

    // The new divider shifts every sibling, not only the two new panes. The tree must still fit,
    // or the layout would hold the others at their minimum and squeeze these two below theirs.
    let needed = candidate.minimumSize(metrics)

    guard needed.width <= size.width + Self.tolerance, needed.height <= size.height + Self.tolerance
    else { throw PaneTreeError.belowMinimumSize(target) }

    root = candidate
    self.allocator = allocator
    return newPane
  }

  /// True when `split(_:axis:in:)` would succeed.
  public func canSplit(_ target: NodeID, axis: Axis, in size: CGSize) -> Bool {
    var copy = self
    return (try? copy.split(target, axis: axis, in: size)) != nil
  }

  // MARK: Close

  /// Removes a pane. Its space goes to the siblings on either side, half to each. A pane with one
  /// neighbor gives all of it to that neighbor. A split left with one child collapses.
  public mutating func close(_ target: NodeID) throws -> CloseOutcome {
    guard root.paneIDs.contains(target) else { throw PaneTreeError.unknownPane(target) }

    guard case .split(let split) = root else { return .lastPane }

    var focus: NodeID?
    let removed = split.removing(target, focus: &focus)

    root = removed.normalizedRoot()
    parked.insert(target)

    guard let focus else { preconditionFailure("a removed pane always names the pane after it") }

    return .closed(focus: focus)
  }

  // MARK: Placement

  /// Where a pane sits now, in a form that `insert(_:at:in:)` can use after the tree has changed.
  /// The only pane has no place to come back to, so it answers nil.
  public func placement(of pane: NodeID) -> PanePlacement? {
    root.placement(of: pane)
  }

  /// Lets go of a closed pane for good. Its ID is retired, and `insert(_:at:in:)` refuses it from
  /// now on. Retiring an ID that is not parked changes nothing.
  public mutating func retire(_ pane: NodeID) {
    parked.remove(pane)
  }

  /// Brings a pane back. Pass the ID of a pane that was closed and not retired to keep it, or nil
  /// to make a new pane with a fresh ID.
  ///
  /// The pane goes beside the placement's neighbor on its side. When the neighbor now sits in a
  /// split of another axis, or is the root, the neighbor is wrapped in a new split along the
  /// placement's axis. When the neighbor is gone, the pane goes to the edge of the whole tree on
  /// the placement's side. The pane takes the placement's weight, and its siblings share the rest.
  /// When that leaves a pane below the minimum, an equal share is tried. When that fails too, the
  /// insert is refused. Nothing changes then, and no ID is used.
  @discardableResult
  public mutating func insert(
    _ pane: NodeID?, at placement: PanePlacement, in size: CGSize
  ) throws -> NodeID {
    if let pane {
      guard pane.rawValue > 0, pane.rawValue <= allocator.highWaterMark else {
        throw PaneTreeError.neverIssued(pane)
      }

      guard !root.contains(pane) else { throw PaneTreeError.alreadyInTree(pane) }
      guard parked.contains(pane) else { throw PaneTreeError.retired(pane) }
    }

    let recorded = placement.weight > 0 && placement.weight < 1
    let weights: [Double?] = recorded ? [placement.weight, nil] : [nil]

    for weight in weights {
      var allocator = self.allocator
      let id = pane ?? allocator.next()
      let candidate = root.inserting(id, at: placement, weight: weight, allocator: &allocator)

      guard fits(candidate, in: size) else { continue }

      root = candidate
      self.allocator = allocator
      parked.remove(id)
      return id
    }

    throw PaneTreeError.belowMinimumSize(placement.neighbor)
  }

  /// True when `insert(_:at:in:)` would succeed.
  public func canInsert(_ pane: NodeID?, at placement: PanePlacement, in size: CGSize) -> Bool {
    var copy = self
    return (try? copy.insert(pane, at: placement, in: size)) != nil
  }

  /// True when every pane of `candidate` keeps its minimum at `size`, and the whole tree fits.
  private func fits(_ candidate: Node, in size: CGSize) -> Bool {
    let ideal = layout(in: size, clamped: false, of: candidate)
    let minimum = metrics.minimumPaneSize

    for id in candidate.paneIDs {
      guard let frame = ideal.frames[id], frame.width >= minimum.width - Self.tolerance,
        frame.height >= minimum.height - Self.tolerance
      else { return false }
    }

    let needed = candidate.minimumSize(metrics)
    return needed.width <= size.width + Self.tolerance
      && needed.height <= size.height + Self.tolerance
  }

  // MARK: Divider

  /// Moves a divider by `delta` points. Space moves between the two adjacent children, and no
  /// other child changes. The move stops where either child would drop below its minimum.
  /// Returns the distance the divider moved.
  @discardableResult
  public mutating func moveDivider(
    between leading: NodeID, and trailing: NodeID, by delta: CGFloat, in size: CGSize
  ) throws -> CGFloat {
    guard let split = root.split(holding: leading, then: trailing) else {
      throw PaneTreeError.notAdjacent(leading, trailing)
    }

    let current = layout(in: size)

    guard let leadingFrame = current.frames[leading], let trailingFrame = current.frames[trailing],
      let leadingNode = root.find(leading), let trailingNode = root.find(trailing)
    else { throw PaneTreeError.notAdjacent(leading, trailing) }

    let axis = split.axis
    let leadingLength = leadingFrame.length(along: axis)
    let total = leadingLength + trailingFrame.length(along: axis)
    let lower = leadingNode.minimumSize(metrics).length(along: axis)
    let upper = total - trailingNode.minimumSize(metrics).length(along: axis)

    guard lower <= upper, total > 0 else { return 0 }

    let moved = min(max(leadingLength + delta, lower), upper)

    let leadingWeight = split.children.first { $0.node.id == leading }?.weight ?? 0
    let trailingWeight = split.children.first { $0.node.id == trailing }?.weight ?? 0
    let pair = leadingWeight + trailingWeight
    let newLeading = pair * Double(moved / total)

    root = root.settingWeights(
      split: split.id, leading: (leading, newLeading), trailing: (trailing, pair - newLeading))

    return moved - leadingLength
  }

  // MARK: Focus order

  /// The pane after `id` in reading order, wrapping around.
  public func nextPane(after id: NodeID) -> NodeID? {
    let ids = paneIDs
    guard let index = ids.firstIndex(of: id) else { return nil }

    return ids[(index + 1) % ids.count]
  }

  /// The pane before `id` in reading order, wrapping around.
  public func previousPane(before id: NodeID) -> NodeID? {
    let ids = paneIDs
    guard let index = ids.firstIndex(of: id) else { return nil }

    return ids[(index + ids.count - 1) % ids.count]
  }

  /// The nearest pane in `direction` whose span overlaps the pane's own. Among equals, the one with
  /// the larger overlap wins, then the one nearer the top left.
  public func neighbor(of id: NodeID, toward direction: Direction, in size: CGSize) -> NodeID? {
    let frames = layout(in: size).frames
    guard let origin = frames[id] else { return nil }

    var best: (id: NodeID, distance: CGFloat, overlap: CGFloat, frame: CGRect)?

    for candidate in paneIDs where candidate != id {
      guard let frame = frames[candidate] else { continue }

      let distance: CGFloat
      let overlap: CGFloat

      switch direction {
      case .right:
        distance = frame.minX - origin.maxX
        overlap = Self.overlap(origin.minY, origin.maxY, frame.minY, frame.maxY)

      case .left:
        distance = origin.minX - frame.maxX
        overlap = Self.overlap(origin.minY, origin.maxY, frame.minY, frame.maxY)

      case .down:
        distance = frame.minY - origin.maxY
        overlap = Self.overlap(origin.minX, origin.maxX, frame.minX, frame.maxX)

      case .up:
        distance = origin.minY - frame.maxY
        overlap = Self.overlap(origin.minX, origin.maxX, frame.minX, frame.maxX)
      }

      guard distance >= -Self.tolerance, overlap > Self.tolerance else { continue }

      if let current = best {
        let nearer = distance < current.distance - Self.tolerance
        let sameDistance = abs(distance - current.distance) <= Self.tolerance
        let moreOverlap = overlap > current.overlap + Self.tolerance
        let sameOverlap = abs(overlap - current.overlap) <= Self.tolerance
        let nearerOrigin =
          (frame.minY, frame.minX) < (current.frame.minY, current.frame.minX)

        guard nearer || (sameDistance && (moreOverlap || (sameOverlap && nearerOrigin))) else {
          continue
        }
      }

      best = (candidate, distance, overlap, frame)
    }

    return best?.id
  }

  private static func overlap(
    _ lowA: CGFloat, _ highA: CGFloat, _ lowB: CGFloat, _ highB: CGFloat
  ) -> CGFloat {
    max(0, min(highA, highB) - max(lowA, lowB))
  }

  static let tolerance: CGFloat = 0.000_1
}

// MARK: Recursive edits

extension Node {
  /// Where `target` sits, as a neighbor and a side. Returns nil when it is not a child of a split.
  func placement(of target: NodeID) -> PanePlacement? {
    guard case .split(let split) = self else { return nil }

    if let index = split.children.firstIndex(where: { $0.node.id == target }),
      case .pane = split.children[index].node
    {
      let weight = split.children[index].weight

      if index > 0 {
        return PanePlacement(
          neighbor: split.children[index - 1].node.id, axis: split.axis, side: .after,
          weight: weight)
      }

      return PanePlacement(
        neighbor: split.children[index + 1].node.id, axis: split.axis, side: .before,
        weight: weight)
    }

    for child in split.children {
      if let found = child.node.placement(of: target) { return found }
    }

    return nil
  }

  /// This node with `pane` added as the placement describes. The result is a normalized root.
  func inserting(
    _ pane: NodeID, at placement: PanePlacement, weight: Double?, allocator: inout NodeIDAllocator
  ) -> Node {
    let axis = placement.axis
    let side = placement.side

    if id == placement.neighbor {
      return wrapping(pane, axis: axis, side: side, weight: weight, allocator: &allocator)
        .normalizedRoot()
    }

    if let found = inserting(
      pane, beside: placement.neighbor, axis: axis, side: side, weight: weight,
      allocator: &allocator)
    {
      return found.normalizedRoot()
    }

    if case .split(var split) = self, split.axis == axis {
      split.addChild(pane, at: side == .before ? 0 : split.children.count, weight: weight)
      let edited: Node = .split(split)
      return edited.normalizedRoot()
    }

    return wrapping(pane, axis: axis, side: side, weight: weight, allocator: &allocator)
      .normalizedRoot()
  }

  private func inserting(
    _ pane: NodeID, beside neighbor: NodeID, axis: Axis, side: Side, weight: Double?,
    allocator: inout NodeIDAllocator
  ) -> Node? {
    guard case .split(var split) = self else { return nil }

    if let index = split.children.firstIndex(where: { $0.node.id == neighbor }) {
      if split.axis == axis {
        split.addChild(pane, at: side == .before ? index : index + 1, weight: weight)
      } else {
        split.children[index].node = split.children[index].node.wrapping(
          pane, axis: axis, side: side, weight: weight, allocator: &allocator)
      }

      return .split(split)
    }

    for index in split.children.indices where split.children[index].node.contains(neighbor) {
      guard
        let replaced = split.children[index].node.inserting(
          pane, beside: neighbor, axis: axis, side: side, weight: weight, allocator: &allocator)
      else { return nil }

      split.children[index].node = replaced
      return .split(split)
    }

    return nil
  }

  /// A new split along `axis` that holds this node and the new pane. An unrecorded weight gives each
  /// half.
  private func wrapping(
    _ pane: NodeID, axis: Axis, side: Side, weight: Double?, allocator: inout NodeIDAllocator
  ) -> Node {
    let share = weight ?? 0.5
    let added = Child(node: .pane(Pane(id: pane)), weight: share)
    let existing = Child(node: self, weight: 1 - share)

    return .split(
      Split(
        id: allocator.next(), axis: axis,
        children: side == .before ? [added, existing] : [existing, added]))
  }

  /// Splits the pane `target` under this node. Returns nil when the pane is not here.
  func splitting(
    _ target: NodeID, axis: Axis, newPane: NodeID, allocator: inout NodeIDAllocator
  ) -> Node? {
    switch self {
    case .pane(let pane):
      guard pane.id == target else { return nil }

      return .split(
        Split(
          id: allocator.next(), axis: axis,
          children: [
            Child(node: self, weight: 0.5), Child(node: .pane(Pane(id: newPane)), weight: 0.5),
          ]
        ))

    case .split(var split):
      guard let index = split.children.firstIndex(where: { $0.node.contains(target) }) else {
        return nil
      }

      let child = split.children[index]

      if case .pane = child.node, split.axis == axis {
        let half = child.weight / 2
        split.children[index].weight = half
        split.children.insert(
          Child(node: .pane(Pane(id: newPane)), weight: half), at: index + 1)
      } else if let replaced = child.node.splitting(
        target, axis: axis, newPane: newPane, allocator: &allocator)
      {
        split.children[index].node = replaced
      } else {
        return nil
      }

      return .split(split)
    }
  }

  /// The split that holds `leading` immediately followed by `trailing`.
  func split(holding leading: NodeID, then trailing: NodeID) -> Split? {
    guard case .split(let split) = self else { return nil }

    let ids = split.children.map { $0.node.id }
    if let index = ids.firstIndex(of: leading), index + 1 < ids.count, ids[index + 1] == trailing {
      return split
    }

    for child in split.children {
      if let found = child.node.split(holding: leading, then: trailing) { return found }
    }

    return nil
  }

  func settingWeights(
    split target: NodeID, leading: (NodeID, Double), trailing: (NodeID, Double)
  ) -> Node {
    guard case .split(var split) = self else { return self }

    if split.id == target {
      for index in split.children.indices {
        switch split.children[index].node.id {
        case leading.0: split.children[index].weight = leading.1
        case trailing.0: split.children[index].weight = trailing.1
        default: break
        }
      }
    } else {
      for index in split.children.indices {
        split.children[index].node = split.children[index].node.settingWeights(
          split: target, leading: leading, trailing: trailing)
      }
    }

    return .split(split)
  }
}

extension Split {
  /// Adds a pane child at `index`. The pane takes `weight`, and the other children share the rest in
  /// proportion. Without a weight, the pane takes an equal share.
  mutating func addChild(_ pane: NodeID, at index: Int, weight: Double?) {
    let share = weight ?? 1 / Double(children.count + 1)

    for position in children.indices {
      children[position].weight *= 1 - share
    }

    children.insert(Child(node: .pane(Pane(id: pane)), weight: share), at: index)
  }

  /// Removes the pane from this split or a split below it. The result may need normalizing.
  func removing(_ target: NodeID, focus: inout NodeID?) -> Node {
    var split = self

    if let index = split.children.firstIndex(where: { $0.node.id == target }),
      case .pane = split.children[index].node
    {
      let weight = split.children[index].weight
      let previous = index > 0 ? index - 1 : nil
      let next = index + 1 < split.children.count ? index + 1 : nil

      switch (previous, next) {
      case (let previous?, let next?):
        split.children[previous].weight += weight / 2
        split.children[next].weight += weight / 2
        focus = split.children[previous].node.paneIDs.last

      case (let previous?, nil):
        split.children[previous].weight += weight
        focus = split.children[previous].node.paneIDs.last

      case (nil, let next?):
        split.children[next].weight += weight
        focus = split.children[next].node.paneIDs.first

      case (nil, nil):
        break
      }

      split.children.remove(at: index)
      return .split(split)
    }

    for index in split.children.indices where split.children[index].node.contains(target) {
      if case .split(let inner) = split.children[index].node {
        split.children[index].node = inner.removing(target, focus: &focus)
      }
    }

    return .split(split)
  }
}

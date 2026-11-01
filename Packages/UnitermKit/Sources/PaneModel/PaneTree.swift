import CoreGraphics
import Foundation

public enum PaneTreeError: Error, Equatable {
  case unknownPane(NodeID)

  /// The split would leave a pane smaller than the minimum. The pane named is the one that was
  /// split, or the new one when it is the one that is too small.
  case belowMinimumSize(NodeID)

  /// The two nodes are not neighbors under one split.
  case notAdjacent(NodeID, NodeID)
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

  /// The largest ID ever handed out. A saved layout stores it.
  public var highWaterMark: UInt64 { allocator.highWaterMark }

  /// Makes a tree with one pane.
  public init(metrics: PaneMetrics = .standard, allocator: NodeIDAllocator = NodeIDAllocator()) {
    var allocator = allocator
    self.root = .pane(Pane(id: allocator.next()))
    self.metrics = metrics
    self.allocator = allocator
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

    guard let focus else { preconditionFailure("a removed pane always names the pane after it") }

    return .closed(focus: focus)
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

import AppletKit
import CoreGraphics
import Foundation
import PaneModel

/// A pane or a split, as the layout file holds it.
public indirect enum SavedNode: Sendable, Equatable {
  case pane(id: NodeID, applet: AppletDescription)
  case split(id: NodeID, axis: Axis, children: [SavedChild])

  /// The IDs of every node under this one, in file order.
  var allIDs: [NodeID] {
    switch self {
    case .pane(let id, _):
      return [id]

    case .split(let id, _, let children):
      return [id] + children.flatMap { $0.node.allIDs }
    }
  }

  /// The IDs of the panes under this node, in reading order.
  public var paneIDs: [NodeID] {
    switch self {
    case .pane(let id, _): return [id]
    case .split(_, _, let children): return children.flatMap { $0.node.paneIDs }
    }
  }
}

public struct SavedChild: Sendable, Equatable {
  public var node: SavedNode
  public var weight: Double

  public init(node: SavedNode, weight: Double) {
    self.node = node
    self.weight = weight
  }
}

/// One window of the saved layout.
public struct SavedWindow: Sendable, Equatable {
  /// The window's frame in screen coordinates.
  public var frame: CGRect

  /// The frame of the screen the window was on, when it was on one.
  public var screen: CGRect?

  public var tree: SavedNode

  /// The pane that had focus, when it is a pane of the tree.
  public var focusedPane: NodeID?

  /// The largest node ID the window's tree ever handed out. A restored tree starts its allocator
  /// from it, so an ID that was retired before the quit is never issued again. A closed pane is not
  /// in the file, and its ID stays below the mark. Each window has its own tree and so its own mark.
  public var highWaterMark: UInt64

  public init(
    frame: CGRect, screen: CGRect?, tree: SavedNode, focusedPane: NodeID?, highWaterMark: UInt64
  ) {
    self.frame = frame
    self.screen = screen
    self.tree = tree
    self.focusedPane = focusedPane
    self.highWaterMark = max(highWaterMark, tree.allIDs.map(\.rawValue).max() ?? 0)
  }
}

/// Everything the layout file holds: the windows.
public struct SavedLayout: Sendable, Equatable {
  public var windows: [SavedWindow]

  public init(windows: [SavedWindow]) {
    self.windows = windows
  }
}

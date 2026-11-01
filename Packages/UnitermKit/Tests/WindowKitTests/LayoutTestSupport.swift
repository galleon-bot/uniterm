import AppletKit
import CoreGraphics
import LayoutKit
import PaneModel

/// A saved pane whose description is a fake applet titled with the name and the ID.
func savedPane(_ id: UInt64, _ name: String = "p") -> SavedNode {
  .pane(
    id: NodeID(rawValue: id),
    applet: AppletDescription(type: "fake", version: 1, payload: .string("\(name)\(id)")))
}

func savedSplit(_ id: UInt64, _ axis: Axis, _ children: [(SavedNode, Double)]) -> SavedNode {
  .split(
    id: NodeID(rawValue: id), axis: axis,
    children: children.map { SavedChild(node: $0.0, weight: $0.1) })
}

func savedWindow(
  tree: SavedNode, focus: UInt64? = nil, mark: UInt64 = 0,
  frame: CGRect = CGRect(x: 100, y: 200, width: 900, height: 600)
) -> SavedWindow {
  SavedWindow(
    frame: frame, screen: CGRect(x: 0, y: 0, width: 1440, height: 900), tree: tree,
    focusedPane: focus.map { NodeID(rawValue: $0) }, highWaterMark: mark)
}

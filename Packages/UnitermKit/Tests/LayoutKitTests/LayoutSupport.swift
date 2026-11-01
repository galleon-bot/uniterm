import AppletKit
import CoreGraphics
import Foundation
import LayoutKit
import PaneModel
import XCTest

func fakeDescription(_ title: String) -> AppletDescription {
  AppletDescription(type: "fake", version: 1, payload: .string(title))
}

func pane(_ id: UInt64, _ title: String = "p") -> SavedNode {
  .pane(id: NodeID(rawValue: id), applet: fakeDescription("\(title)\(id)"))
}

func split(_ id: UInt64, _ axis: Axis, _ children: [(SavedNode, Double)]) -> SavedNode {
  .split(
    id: NodeID(rawValue: id), axis: axis,
    children: children.map { SavedChild(node: $0.0, weight: $0.1) })
}

func window(
  tree: SavedNode, focus: UInt64? = nil, mark: UInt64 = 0,
  frame: CGRect = CGRect(x: 100, y: 200, width: 900, height: 600)
) -> SavedWindow {
  SavedWindow(
    frame: frame, screen: CGRect(x: 0, y: 0, width: 1440, height: 900), tree: tree,
    focusedPane: focus.map { NodeID(rawValue: $0) }, highWaterMark: mark)
}

/// A scratch folder that goes away with the test.
func makeScratch(_ test: XCTestCase) throws -> URL {
  let url = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("uniterm-layout-test-\(UUID().uuidString)", isDirectory: true)

  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  test.addTeardownBlock { try? FileManager.default.removeItem(at: url) }
  return url
}

func permissions(of url: URL) throws -> Int {
  let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
  return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

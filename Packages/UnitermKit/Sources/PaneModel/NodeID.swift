import CoreGraphics
import Foundation

/// The identity of a node in the pane tree.
///
/// An ID names one node for as long as the node exists. A node that survives a split, a merge, or a
/// collapse keeps its ID. A removed node's ID is retired and never handed out again.
public struct NodeID: Hashable, Comparable, Sendable, CustomStringConvertible {
  public let rawValue: UInt64

  public init(rawValue: UInt64) {
    self.rawValue = rawValue
  }

  public static func < (lhs: NodeID, rhs: NodeID) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  public var description: String { "\(rawValue)" }
}

/// Hands out node IDs in increasing order.
///
/// The high-water mark is the largest ID ever handed out. A saved layout stores it, and a restored
/// allocator starts from it, so an ID retired before a quit is never reissued.
public struct NodeIDAllocator: Sendable, Equatable {
  public private(set) var highWaterMark: UInt64

  public init(highWaterMark: UInt64 = 0) {
    self.highWaterMark = highWaterMark
  }

  public mutating func next() -> NodeID {
    highWaterMark += 1
    return NodeID(rawValue: highWaterMark)
  }
}

import CoreGraphics
import Foundation

/// The direction a split lays out its children.
public enum Axis: Sendable, Equatable {
  /// Children sit side by side, left to right.
  case row

  /// Children are stacked, top to bottom.
  case column

  public var crossed: Axis {
    self == .row ? .column : .row
  }
}

public enum Direction: Sendable, Equatable, CaseIterable {
  case left
  case right
  case up
  case down
}

/// The sizes that shape a layout.
public struct PaneMetrics: Sendable, Equatable {
  /// The smallest a pane may be. A split that would push a pane below it is refused.
  public var minimumPaneSize: CGSize

  /// The gap between two siblings. A divider fills it.
  public var dividerThickness: CGFloat

  public init(minimumPaneSize: CGSize, dividerThickness: CGFloat) {
    self.minimumPaneSize = minimumPaneSize
    self.dividerThickness = dividerThickness
  }

  /// A pane keeps room for about 24 columns and 6 rows of terminal text at the default font.
  public static let standard = PaneMetrics(
    minimumPaneSize: CGSize(width: 200, height: 100), dividerThickness: 5)
}

extension CGSize {
  func length(along axis: Axis) -> CGFloat {
    axis == .row ? width : height
  }
}

extension CGRect {
  func length(along axis: Axis) -> CGFloat {
    axis == .row ? width : height
  }
}

import Preferences

/// What a docked region is for. A region's role never changes. Where it docks is a separate
/// setting.
///
/// The pane area is not a role. It fills whatever the docked regions leave. The command palette
/// and the widget bar join as new roles. Adding one adds a case here and a view to the window. The
/// status bar and the pane area do not change.
enum RegionRole: Hashable, Sendable {
  case statusBar
}

/// The edge of the window that a docked region sits against.
enum DockEdge: Hashable, Sendable {
  case top
  case bottom

  init(_ position: StatusBarPosition) {
    switch position {
    case .top: self = .top
    case .bottom: self = .bottom
    }
  }
}

/// A region docked against an edge.
struct RegionPlacement: Equatable, Sendable {
  var role: RegionRole
  var edge: DockEdge
}

/// Orders docked regions against each edge. It is pure, so a test reads it without any views.
enum RegionStack {
  /// Each list runs from the window's edge inward. Regions on one edge keep the order they were
  /// given in.
  static func order(_ placements: [RegionPlacement]) -> (top: [RegionRole], bottom: [RegionRole]) {
    (
      top: placements.filter { $0.edge == .top }.map(\.role),
      bottom: placements.filter { $0.edge == .bottom }.map(\.role)
    )
  }
}

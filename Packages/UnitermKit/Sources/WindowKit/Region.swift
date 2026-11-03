import Preferences

/// What a docked region is for. A region's role never changes. Where it docks is a separate
/// setting.
///
/// The pane area is not a role. It fills whatever the docked regions leave. The widget bar joins
/// as a new role. Adding one adds a case here and a view to the window. The existing regions and
/// the pane area do not change.
enum RegionRole: Hashable, Sendable {
  case statusBar
  case commandPalette

  /// How far from the window's edge the role sits when two share an edge. The status bar is the
  /// window's chrome, so it takes the edge. The palette sits inward, next to the content, where the
  /// results it opens stay beside the panes they cover.
  fileprivate var depth: Int {
    switch self {
    case .statusBar: return 0
    case .commandPalette: return 1
    }
  }
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

  init(_ edge: PaletteDockEdge) {
    switch edge {
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
  /// Each list runs from the window's edge inward. Regions on one edge sit in the order of their
  /// roles' depth, whatever order they were installed in.
  static func order(_ placements: [RegionPlacement]) -> (top: [RegionRole], bottom: [RegionRole]) {
    func inward(_ edge: DockEdge) -> [RegionRole] {
      placements.filter { $0.edge == edge }.map(\.role).sorted { $0.depth < $1.depth }
    }

    return (top: inward(.top), bottom: inward(.bottom))
  }
}

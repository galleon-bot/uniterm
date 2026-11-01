import AppletKit
import Foundation
import PaneModel

/// How many closes a window remembers.
public struct CloseUndoPolicy: Sendable, Equatable {
  public var stackDepth: Int

  public init(stackDepth: Int) {
    self.stackDepth = stackDepth
  }

  public static let standard = CloseUndoPolicy(stackDepth: 20)
}

/// A closed pane, as undo needs it: where it sat, and what it was. The pane's applet is gone.
struct ClosedPane: Equatable {
  let placement: PanePlacement
  let description: AppletDescription
  let title: String
}

/// One window's stack of closed panes, newest last.
///
/// Undo opens a new pane from the newest entry. The pane gets a new ID, since the closed pane's ID
/// is retired.
struct CloseUndoLedger {
  let policy: CloseUndoPolicy

  /// Oldest first.
  private(set) var entries: [ClosedPane] = []

  init(policy: CloseUndoPolicy) {
    self.policy = policy
  }

  var newest: ClosedPane? { entries.last }

  /// Adds a close. The oldest entries drop when the stack is deeper than the policy.
  mutating func push(_ closed: ClosedPane) {
    entries.append(closed)

    if entries.count > policy.stackDepth {
      entries.removeFirst(entries.count - policy.stackDepth)
    }
  }

  mutating func removeNewest() {
    _ = entries.popLast()
  }

  mutating func removeAll() {
    entries = []
  }
}

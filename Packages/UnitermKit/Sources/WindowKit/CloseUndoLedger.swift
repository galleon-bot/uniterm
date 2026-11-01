import AppletKit
import Foundation
import PaneModel

/// How long a closed pane can be undone, and how many closes are remembered.
public struct CloseUndoPolicy: Sendable, Equatable {
  /// How many closed panes stay alive, hidden, at once.
  public var graceSlots: Int

  /// How long a hidden pane stays alive, in seconds.
  public var gracePeriod: TimeInterval

  /// How many closes the window remembers as descriptions, after the grace tier.
  public var stackDepth: Int

  public init(graceSlots: Int, gracePeriod: TimeInterval, stackDepth: Int) {
    self.graceSlots = graceSlots
    self.gracePeriod = gracePeriod
    self.stackDepth = stackDepth
  }

  public static let standard = CloseUndoPolicy(graceSlots: 3, gracePeriod: 10, stackDepth: 20)
}

/// A closed pane, as undo needs it: where it sat, and what it was.
struct ClosedPane: Equatable {
  /// The pane's ID while it lived. A reattach keeps it. A reopen gets a new one.
  let paneID: NodeID
  let placement: PanePlacement
  let description: AppletDescription
  let title: String

  /// Orders closes across both tiers. A higher number closed later.
  let serial: Int
}

/// A closed pane whose applet is alive, hidden, until its deadline.
struct HiddenPane {
  let closed: ClosedPane
  let applet: any Applet
  let deadline: TimeInterval
}

/// The newest close in either tier.
enum UndoEntry {
  case hidden(HiddenPane)
  case described(ClosedPane)
}

/// One window's two undo tiers.
///
/// A closed pane first stays alive and hidden, in a bounded number of slots. After that only its
/// description stays, on a stack of bounded depth. The ledger decides nothing about time or applets.
/// The window tells it the time and does the closing.
struct CloseUndoLedger {
  let policy: CloseUndoPolicy

  /// Hidden panes, oldest first.
  private(set) var hidden: [HiddenPane] = []

  /// Descriptions, oldest first.
  private(set) var described: [ClosedPane] = []

  private var serial = 0

  init(policy: CloseUndoPolicy) {
    self.policy = policy
  }

  mutating func nextSerial() -> Int {
    serial += 1
    return serial
  }

  var hasFreeSlot: Bool { hidden.count < policy.graceSlots }

  /// The soonest deadline among the hidden panes.
  var nextDeadline: TimeInterval? { hidden.map(\.deadline).min() }

  /// The latest close in either tier.
  var newest: UndoEntry? {
    let latestHidden = hidden.max { $0.closed.serial < $1.closed.serial }
    let latestDescribed = described.last

    switch (latestHidden, latestDescribed) {
    case (let hiddenPane?, let describedPane?):
      return hiddenPane.closed.serial > describedPane.serial
        ? .hidden(hiddenPane) : .described(describedPane)

    case (let hiddenPane?, nil):
      return .hidden(hiddenPane)

    case (nil, let describedPane?):
      return .described(describedPane)

    case (nil, nil):
      return nil
    }
  }

  func hiddenPane(for applet: any Applet) -> HiddenPane? {
    hidden.first { $0.applet === applet }
  }

  /// Keeps a closed pane alive. The caller checked `hasFreeSlot`.
  mutating func hide(_ closed: ClosedPane, applet: any Applet, deadline: TimeInterval) {
    hidden.append(HiddenPane(closed: closed, applet: applet, deadline: deadline))
  }

  /// Takes a hidden pane out without keeping its description.
  @discardableResult
  mutating func unhide(_ applet: any Applet) -> HiddenPane? {
    guard let index = hidden.firstIndex(where: { $0.applet === applet }) else { return nil }

    return hidden.remove(at: index)
  }

  /// Puts a description on the stack. The oldest drop when the stack is deeper than the policy.
  mutating func describe(_ closed: ClosedPane) {
    described.append(closed)

    if described.count > policy.stackDepth {
      described.removeFirst(described.count - policy.stackDepth)
    }
  }

  mutating func removeDescribed(serial: Int) {
    described.removeAll { $0.serial == serial }
  }

  /// Takes out every hidden pane whose deadline has come.
  mutating func takeExpired(at now: TimeInterval) -> [HiddenPane] {
    let expired = hidden.filter { $0.deadline <= now }
    hidden.removeAll { $0.deadline <= now }
    return expired
  }

  /// Takes out every hidden pane.
  mutating func takeAllHidden() -> [HiddenPane] {
    let all = hidden
    hidden = []
    return all
  }

  mutating func removeAll() {
    hidden = []
    described = []
  }
}

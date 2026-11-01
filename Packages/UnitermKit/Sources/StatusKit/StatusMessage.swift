import Foundation

/// How serious a status message is. The level sets its style. Messages carry no priority.
public enum StatusLevel: Int, Sendable, Comparable {
  case info
  case warning
  case error

  public static func < (lhs: StatusLevel, rhs: StatusLevel) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

/// Who posted a message. The bar and the history show it, so an untrusted program cannot pass its
/// text off as uniterm's own.
public enum StatusSource: Sendable, Equatable {
  case pane(id: UInt64, name: String)
  case applet(name: String)
  case script(name: String)
  case uniterm

  public var label: String {
    switch self {
    case .pane(_, let name): return name
    case .applet(let name): return name
    case .script(let name): return name
    case .uniterm: return "uniterm"
    }
  }

  /// The pane that posted, or nil for any other source.
  public var paneID: UInt64? {
    guard case .pane(let id, _) = self else { return nil }

    return id
  }
}

public struct StatusMessage: Sendable, Equatable, Identifiable {
  public let id: UInt64
  public let level: StatusLevel
  public let source: StatusSource
  public let text: String

  /// Seconds on the queue's clock.
  public let postedAt: TimeInterval
}

/// A message on the bar, with the count of older errors folded into it.
public struct StatusDisplay: Sendable, Equatable {
  public let message: StatusMessage
  public let collapsedErrors: Int
}

/// The bounds that shape the queue. A caller changes them only in tests.
public struct StatusPolicy: Sendable, Equatable {
  /// How long a message stays before the next queued one may replace it.
  public var minimumDwell: TimeInterval = 1.5

  /// How long an info or warning message stays once the queue is empty.
  public var idleTimeout: TimeInterval = 5

  /// The pending count above which the bar skips to the newest message.
  public var backlogLimit = 3

  /// The most messages the history keeps.
  public var historyLimit = 500

  public static let standard = StatusPolicy()

  public init() {}
}

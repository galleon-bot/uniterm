import AppletKit
import StatusKit

/// Names a slot of the status bar. The window owns its slots. The focused pane's applet fills the
/// applet slots. A later slot joins as a new case.
enum BarSegmentID: Hashable, Sendable {
  case message
  case dismiss
  case unseenError
  case grace
  case graceHangUp
  case applet(Int)

  var identifier: String {
    switch self {
    case .message: return "status-message"
    case .dismiss: return "status-dismiss"
    case .unseenError: return "status-unseen-error"
    case .grace: return "status-grace"
    case .graceHangUp: return "status-grace-hangup"
    case .applet(let index): return "status-applet-\(index)"
    }
  }
}

/// The closed panes that are still alive, hidden, in a window. The status bar shows them so the
/// user knows processes are running that the window does not display.
struct GraceIndicator: Equatable, Sendable {
  var count: Int

  /// Seconds until the first of them is hung up, rounded up.
  var secondsLeft: Int

  var text: String {
    let noun = count == 1 ? "closed pane" : "closed panes"
    return "\(count) \(noun) kept for \(secondsLeft)s. Cmd-Z undoes"
  }
}

/// How a segment is colored and weighted. The bar maps a tone to a theme token.
enum BarTone: Sendable, Equatable {
  case normal
  case emphasized
  case warning
  case error
}

/// One slot of the status bar: a small icon, one line of text, or both.
struct BarSegment: Sendable, Equatable {
  var id: BarSegmentID
  var symbolName: String?
  var text: String?
  var tone: BarTone
  var accessibilityLabel: String?
}

/// Works out what the status bar shows. It is pure, so a test needs no window.
enum StatusBarContent {
  /// The window's slots in order: the message area, a dismiss control while an error is on the
  /// bar, the unseen-error indicator, the undo grace period with its hang-up control, then the
  /// focused applet's slots. The message area is always there, empty when the bar is idle, so the
  /// layout does not jump when a message arrives. The grace slots belong to the window, not to the
  /// message queue, so a flood of messages never displaces them.
  static func segments(
    display: StatusDisplay?, hasUnseenError: Bool, grace: GraceIndicator? = nil,
    applet: [AppletSegment]
  ) -> [BarSegment] {
    var result = [message(display)]

    if display?.message.level == .error {
      result.append(
        BarSegment(
          id: .dismiss, symbolName: "xmark.circle", text: nil, tone: .normal,
          accessibilityLabel: "Dismiss message"))
    }

    if hasUnseenError {
      result.append(
        BarSegment(
          id: .unseenError, symbolName: "exclamationmark.circle.fill", text: nil, tone: .error,
          accessibilityLabel: "Unseen errors"))
    }

    if let grace {
      result.append(
        BarSegment(
          id: .grace, symbolName: "arrow.uturn.backward.circle", text: grace.text,
          tone: .emphasized, accessibilityLabel: nil))
      result.append(
        BarSegment(
          id: .graceHangUp, symbolName: "power.circle", text: nil, tone: .warning,
          accessibilityLabel: "Hang up closed panes now"))
    }

    for (index, segment) in applet.enumerated() {
      result.append(
        BarSegment(
          id: .applet(index), symbolName: segment.symbolName, text: segment.text,
          tone: tone(for: segment.style), accessibilityLabel: nil))
    }

    return result
  }

  static func message(_ display: StatusDisplay?) -> BarSegment {
    guard let display else {
      return BarSegment(id: .message, symbolName: nil, text: "", tone: .normal)
    }

    var text = "\(display.message.source.label): \(display.message.text)"
    if display.collapsedErrors > 0 {
      text += "  (+\(display.collapsedErrors) more errors)"
    }

    return BarSegment(
      id: .message, symbolName: symbol(for: display.message.level), text: text,
      tone: tone(for: display.message.level), accessibilityLabel: nil)
  }

  /// One line of the history: the level, the source, and the text.
  static func historyLine(_ message: StatusMessage) -> String {
    "\(name(of: message.level))  \(message.source.label): \(message.text)"
  }

  static func name(of level: StatusLevel) -> String {
    switch level {
    case .info: return "info"
    case .warning: return "warning"
    case .error: return "error"
    }
  }

  static func symbol(for level: StatusLevel) -> String {
    switch level {
    case .info: return "info.circle"
    case .warning: return "exclamationmark.triangle"
    case .error: return "xmark.octagon"
    }
  }

  static func tone(for level: StatusLevel) -> BarTone {
    switch level {
    case .info: return .normal
    case .warning: return .warning
    case .error: return .error
    }
  }

  static func tone(for style: AppletSegment.Style) -> BarTone {
    switch style {
    case .normal: return .normal
    case .emphasized: return .emphasized
    case .warning: return .warning
    case .error: return .error
    }
  }
}

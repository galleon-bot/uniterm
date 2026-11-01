import AppKit
import StatusKit

/// One slot an applet fills in the status bar, such as a mode or a line and column.
public struct AppletSegment: Sendable, Equatable {
  public enum Style: Sendable, Equatable {
    case normal
    case emphasized
    case warning
    case error
  }

  public var symbolName: String?
  public var text: String?
  public var style: Style

  public init(symbolName: String? = nil, text: String? = nil, style: Style = .normal) {
    self.symbolName = symbolName
    self.text = text
    self.style = style
  }
}

/// A question an applet asks the user. The host shows it, names the pane, and returns the answer.
public struct AppletConfirmation: Sendable, Equatable {
  public var title: String
  public var detail: String
  public var confirmTitle: String
  public var cancelTitle: String

  public init(title: String, detail: String, confirmTitle: String, cancelTitle: String) {
    self.title = title
    self.detail = detail
    self.confirmTitle = confirmTitle
    self.cancelTitle = cancelTitle
  }
}

/// The pane side of the applet contract. The host knows which pane an applet runs in, so it fills in
/// the message source.
@MainActor
public protocol AppletHost: AnyObject {
  func applet(_ applet: any Applet, post level: StatusLevel, text: String)

  /// The applet has nothing left to run, so its pane should close.
  func appletDidExit(_ applet: any Applet)

  /// The title or the segments changed.
  func appletDidChange(_ applet: any Applet)

  /// Asks the user. Nothing happens until the user answers.
  func applet(_ applet: any Applet, confirm request: AppletConfirmation) async -> Bool
}

/// What a pane runs. Every applet implements this contract.
///
/// A closed pane's applet is detached and kept alive for a grace period, and reattached on undo.
/// After that, only its description stays.
@MainActor
public protocol Applet: AnyObject {
  var typeID: String { get }

  /// The view the pane hosts. It stays the same for the applet's life.
  var view: NSView { get }

  var title: String { get }
  var segments: [AppletSegment] { get }

  /// True when closing the applet would kill work that undo cannot bring back.
  var isRunningSomething: Bool { get }

  var host: (any AppletHost)? { get set }

  func start()

  /// Ends the applet and everything it runs. The applet is unusable afterwards.
  func close()

  /// Hides the applet and keeps it alive. The host removes its view from the window.
  func detach()

  /// Shows a detached applet again.
  func reattach()

  /// Gives the applet keyboard focus.
  func focus()

  func describe() -> AppletDescription
}

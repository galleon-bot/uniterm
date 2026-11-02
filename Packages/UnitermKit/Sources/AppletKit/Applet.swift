import AppKit
import StatusKit
import Theme

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
/// The host sends the lifecycle events: `start`, `detach`, `reattach`, and `close`. It sends each
/// when it happens and does nothing else on the applet's behalf. It never keeps an applet alive
/// after closing it, and it never stops or signals the applet's work itself. Each applet decides
/// what an event means for its own content.
///
/// Undo reopens a closed pane from its description, in the same place, with the same kind of
/// applet. An applet that wants an undo to bring back more saves it in the description.
@MainActor
public protocol Applet: AnyObject {
  var typeID: String { get }

  /// The view the pane hosts. It stays the same for the applet's life.
  var view: NSView { get }

  var title: String { get }
  var segments: [AppletSegment] { get }

  /// True when closing the applet would kill work that undo cannot bring back.
  var isRunningSomething: Bool { get }

  /// What a confirmation dialog calls the parts of the applet that are running something. An
  /// applet with tabs names each such tab, by title or by command. An applet that is not running
  /// anything names nothing.
  var runningLabels: [String] { get }

  var host: (any AppletHost)? { get set }

  /// The directory the applet's current work is in, as an absolute local path. A new pane opened
  /// from this one starts there. An applet with no such concept, or with no usable directory right
  /// now, returns nil and says nothing.
  var currentDirectory: String? { get }

  /// The applet is in a pane and on screen. It begins its work.
  func start()

  /// The host is done with the applet, and it is unusable afterwards. What the applet does next is
  /// its own choice. It may end its work at once, finish it after a delay, or save more state into
  /// its description. Work it keeps alive after close must be bounded in time and visible to the
  /// user.
  func close()

  /// The applet has left the screen and stays alive. It stops at once what the user would notice
  /// but cannot see. It pauses audio and video, and it holds back alerts. An applet with nothing
  /// perceptible to pause does nothing.
  func detach()

  /// The applet is back on screen. It undoes what `detach` did.
  func reattach()

  /// Gives the applet keyboard focus.
  func focus()

  func describe() -> AppletDescription

  /// Tells the applet the palette to draw its own chrome with. The host calls it when the applet
  /// is installed and whenever the palette changes.
  func apply(_ palette: ThemePalette)
}

extension Applet {
  public func apply(_ palette: ThemePalette) {}

  public var currentDirectory: String? { nil }

  /// An applet with one part running names itself by its title.
  public var runningLabels: [String] {
    isRunningSomething ? [title] : []
  }
}

/// An applet that holds several tabs. The host routes the tab menu items and Cmd-W to it.
///
/// Closing the last tab is not a tab close. It is a pane close, which the host owns.
@MainActor
public protocol TabbedApplet: Applet {
  var tabCount: Int { get }
  var selectedTabIndex: Int { get }

  /// False in a mode that runs one program in one tab.
  var canOpenTab: Bool { get }

  func openTab()

  /// Selects a tab. An index outside the tabs does nothing.
  func selectTab(at index: Int)

  /// Closes the selected tab, after asking when it is running something. Returns false when the
  /// user declined, or when the applet has only one tab.
  func closeSelectedTab() async -> Bool
}

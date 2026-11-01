import AppKit
import Theme

/// What a terminal session starts. The directory and environment are applied to the child process.
public struct TerminalLaunch: Sendable, Equatable {
  public var workingDirectory: String?
  public var environment: [String: String]

  /// Starts the user's default login shell, from `$SHELL` or the passwd entry.
  public static func loginShell(
    workingDirectory: String? = nil, environment: [String: String] = [:]
  ) -> TerminalLaunch {
    TerminalLaunch(workingDirectory: workingDirectory, environment: environment)
  }
}

/// A terminal action that uniterm's own key bindings and menus call.
public enum TerminalAction: Sendable, Equatable, CaseIterable {
  case copy
  case paste
  case selectAll
  case increaseFontSize
  case decreaseFontSize
  case resetFontSize
  case clearScreen
}

public struct TerminalGridSize: Sendable, Equatable {
  public var columns: Int
  public var rows: Int

  public init(columns: Int, rows: Int) {
    self.columns = columns
    self.rows = rows
  }
}

/// A request from the program in the terminal to use the clipboard. The user's answer completes it
/// exactly once. A request that is dropped without an answer stays unanswered.
public final class TerminalClipboardRequest: @unchecked Sendable {
  public enum Kind: Sendable, Equatable {
    /// A program asked to read the clipboard with OSC 52. The text is what it would receive.
    case read
    /// A program asked to write the clipboard with OSC 52.
    case write
    /// A paste that libghostty judged unsafe.
    case unsafePaste
  }

  public let kind: Kind
  public let text: String

  private let lock = NSLock()
  private var completion: (@Sendable (Bool) -> Void)?

  init(kind: Kind, text: String, completion: @escaping @Sendable (Bool) -> Void) {
    self.kind = kind
    self.text = text
    self.completion = completion
  }

  /// Answers the request. A second call does nothing.
  public func resolve(allow: Bool) {
    lock.lock()
    let completion = self.completion
    self.completion = nil
    lock.unlock()

    completion?(allow)
  }
}

/// Something that happened in the terminal. The session reports it on the main actor.
public enum TerminalEvent: Sendable {
  case titleChanged(String)

  /// The shell reported its directory with OSC 7. The value is a path.
  case workingDirectoryChanged(String)

  /// The shell reported that a command ended, with OSC 133. This is the only prompt mark that
  /// libghostty passes to its embedder. Whether the cursor sits at a prompt is answered by
  /// `isRunningSomething`.
  case commandFinished(exitCode: Int?, duration: Duration)

  /// A program sent OSC 9 or OSC 777.
  case notification(title: String, body: String)

  case clipboardRequest(TerminalClipboardRequest)
  case bell

  /// The child process ended. The session is spent and needs `close()`.
  case exited
}

/// One terminal session: a child process on a pty, drawn into a view.
///
/// This is uniterm's boundary with the terminal engine. No engine type appears in it. The session
/// level is the only level that works, since the engine spawns the child and owns the pty.
@MainActor
public protocol TerminalSession: AnyObject {
  var view: NSView { get }

  var onEvent: (@MainActor (TerminalEvent) -> Void)? { get set }

  var title: String { get }
  var workingDirectory: String? { get }
  var gridSize: TerminalGridSize { get }

  /// True unless the cursor sits at an idle shell prompt. Shell integration marks the prompt with
  /// OSC 133. A shell without those marks always reads as running.
  var isRunningSomething: Bool { get }

  var hasExited: Bool { get }

  /// Sends text to the child the way a paste does. A shell with bracketed paste does not run a pasted
  /// newline. Real key presses reach the child through the hosted view.
  func send(text: String)

  func perform(_ action: TerminalAction)

  /// Sets the view's size in points. The child sees the new grid size.
  func resize(to size: CGSize)

  func setFocused(_ focused: Bool)

  /// Tells the renderer whether the view can be seen. A detached session is not visible.
  func setVisible(_ visible: Bool)

  /// Hangs up the child and releases the session. The session is unusable afterwards.
  func close()
}

/// Owns the engine and makes sessions.
@MainActor
public protocol TerminalEngine: AnyObject {
  func makeSession(launch: TerminalLaunch) throws -> any TerminalSession

  /// Updates the palette of every running session, and of sessions made later.
  func apply(palette: ThemePalette) throws

  /// True when any running session is running something.
  var anySessionRunningSomething: Bool { get }
}

/// The menu actions that the focused terminal answers. A menu item with a nil target finds them on
/// the first responder, so uniterm's menu owns the key bindings and the terminal only reacts.
@MainActor @objc public protocol TerminalMenuActions {
  func copy(_ sender: Any?)
  func paste(_ sender: Any?)
  func selectAll(_ sender: Any?)
  func increaseTerminalFontSize(_ sender: Any?)
  func decreaseTerminalFontSize(_ sender: Any?)
  func resetTerminalFontSize(_ sender: Any?)
  func clearTerminalScreen(_ sender: Any?)
}

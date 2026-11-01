import AppKit
import AppletKit
import StatusKit
import TerminalSurface

/// The terminal applet. It talks to the terminal only through the session protocol.
///
/// It runs one shell in one tab. The description already keeps a list of tabs, so tabs and program
/// mode fit later without a new format.
@MainActor
public final class TerminalApplet: Applet {
  /// The longest notification text that reaches the status bar.
  static let maximumMessageLength = 200

  public let typeID = TerminalDescription.typeID
  public let view: NSView = NSView()
  public weak var host: (any AppletHost)?

  public private(set) var title = "Terminal"
  public private(set) var segments: [AppletSegment] = []

  private let engine: any TerminalEngine
  private var launch: TerminalLaunch
  private var session: (any TerminalSession)?
  private var workingDirectory: String?
  private var detached = false

  public init(engine: any TerminalEngine, launch: TerminalLaunch = .loginShell()) {
    self.engine = engine
    self.launch = launch
    self.workingDirectory = launch.workingDirectory
    view.setAccessibilityIdentifier("terminal-applet")
  }

  /// Restores an applet from a description. It starts a fresh shell and runs nothing else.
  public convenience init(engine: any TerminalEngine, restoring description: AppletDescription)
    throws
  {
    let decoded = try TerminalDescription.decode(description)

    guard decoded.mode == .shell else {
      throw AppletRestoreError.unsupported("program-mode terminals are not restorable yet")
    }

    self.init(
      engine: engine,
      launch: .loginShell(workingDirectory: decoded.tabs[decoded.selectedTab].workingDirectory))
  }

  public var isRunningSomething: Bool {
    guard let session, !session.hasExited else { return false }

    return session.isRunningSomething
  }

  public func start() {
    guard session == nil else { return }

    do {
      let session = try engine.makeSession(launch: launch)
      self.session = session
      session.onEvent = { [weak self] event in self?.handle(event) }

      let terminalView = session.view
      terminalView.frame = view.bounds
      terminalView.autoresizingMask = [.width, .height]
      view.addSubview(terminalView)
    } catch {
      host?.applet(self, post: .error, text: "The terminal could not start: \(error)")
      host?.appletDidExit(self)
    }
  }

  public func close() {
    session?.close()
    session = nil
    for subview in view.subviews {
      subview.removeFromSuperview()
    }
  }

  public func detach() {
    detached = true
    session?.setFocused(false)
    session?.setVisible(false)
  }

  public func reattach() {
    detached = false
    session?.setVisible(true)
  }

  public func focus() {
    guard let terminalView = session?.view else { return }

    terminalView.window?.makeFirstResponder(terminalView)
  }

  public func describe() -> AppletDescription {
    let description = TerminalDescription(
      mode: .shell, tabs: [TerminalDescription.Tab(workingDirectory: workingDirectory)])

    do {
      return try description.appletDescription()
    } catch {
      preconditionFailure("a terminal description always encodes: \(error)")
    }
  }

  private func handle(_ event: TerminalEvent) {
    switch event {
    case .titleChanged(let value):
      title = Self.sanitized(value, limit: 80)
      if title.isEmpty { title = "Terminal" }
      host?.appletDidChange(self)

    case .workingDirectoryChanged(let path):
      workingDirectory = path

    case .commandFinished(let exitCode, _):
      if let exitCode, exitCode != 0 {
        segments = [AppletSegment(symbolName: "xmark.circle", text: "\(exitCode)", style: .error)]
      } else {
        segments = []
      }

      host?.appletDidChange(self)

    case .notification(let title, let body):
      let text = [title, body].map { Self.sanitized($0) }.filter { !$0.isEmpty }.joined(
        separator: ": ")
      guard !text.isEmpty else { return }

      host?.applet(self, post: .info, text: text)

    case .clipboardRequest(let request):
      confirm(request)

    case .bell:
      break

    case .exited:
      host?.appletDidExit(self)
    }
  }

  /// A request is never answered without the user's say. With no host to ask, it is refused.
  private func confirm(_ request: TerminalClipboardRequest) {
    guard let host else {
      request.resolve(allow: false)
      return
    }

    let confirmation: AppletConfirmation

    switch request.kind {
    case .read:
      confirmation = AppletConfirmation(
        title: "Allow a program to read your clipboard?",
        detail:
          "A program in this pane asked for the clipboard with an escape sequence. It would receive: \(Self.preview(request.text))",
        confirmTitle: "Allow", cancelTitle: "Deny")

    case .write:
      confirmation = AppletConfirmation(
        title: "Allow a program to change your clipboard?",
        detail:
          "A program in this pane wants to replace the clipboard with: \(Self.preview(request.text))",
        confirmTitle: "Allow", cancelTitle: "Deny")

    case .unsafePaste:
      confirmation = AppletConfirmation(
        title: "Paste text that could run commands?",
        detail:
          "The text holds control characters or a newline. It would be pasted as: \(Self.preview(request.text))",
        confirmTitle: "Paste", cancelTitle: "Cancel")
    }

    Task { @MainActor [weak self] in
      guard let self else {
        request.resolve(allow: false)
        return
      }

      let allowed = await host.applet(self, confirm: confirmation)
      request.resolve(allow: allowed)
    }
  }

  /// Removes control characters and caps the length. Text from a program is untrusted, so it must
  /// not forge a second line in the status bar.
  static func sanitized(_ text: String, limit: Int = maximumMessageLength) -> String {
    let cleaned = text.unicodeScalars.map { scalar -> Character in
      CharacterSet.controlCharacters.contains(scalar) || CharacterSet.newlines.contains(scalar)
        ? " " : Character(scalar)
    }

    let collapsed = String(cleaned).split(separator: " ", omittingEmptySubsequences: true)
      .joined(separator: " ")
    return String(collapsed.prefix(limit))
  }

  private static func preview(_ text: String) -> String {
    let shown = sanitized(text, limit: 120)
    return "\u{201C}\(shown)\u{201D}"
  }
}

import AppKit
import StatusKit

/// Where a new window lands when it cascades from an existing one.
enum WindowCascade {
  /// How far each cascaded window moves right and down.
  static let step: CGFloat = 28

  /// The top-left corner for a window of `size` that follows `anchor`. The window moves one step
  /// right and down. When that would push it past the right or bottom edge of `visible`, it wraps
  /// to the top-left corner of `visible`. Without a visible frame there is no edge to hit.
  static func topLeft(after anchor: NSRect, size: NSSize, in visible: NSRect?) -> NSPoint {
    let x = anchor.minX + step
    let y = anchor.maxY - step

    guard let visible else { return NSPoint(x: x, y: y) }

    if x + size.width <= visible.maxX, y - size.height >= visible.minY {
      return NSPoint(x: x, y: y)
    }

    return NSPoint(x: visible.minX, y: visible.maxY)
  }
}

/// The open main windows, in the order they were opened.
///
/// Each window has its own controller, so its own pane tree, status bar, and status center. The
/// set creates a window, cascades it from the active one, and lets go of its controller when the
/// window closes. Closing the last window leaves the set empty and ends nothing.
@MainActor
public final class WindowSet {
  /// Makes the controller for one window. The identifier names the window to accessibility.
  public typealias Factory = @MainActor (_ identifier: String) throws -> MainWindowController

  /// The open windows' controllers, oldest first. A window leaves the list the moment it closes.
  public private(set) var controllers: [MainWindowController] = []

  private let makeController: Factory
  private let visibleFrame: @MainActor (NSWindow) -> NSRect?
  private var serial = 0

  /// Messages posted while no window was open, oldest first.
  private var held: [(level: StatusLevel, source: StatusSource, text: String)] = []

  /// Controllers whose windows have closed. The window that is closing still calls into its
  /// controller, so the set keeps it alive until the next turn of the main actor.
  private var closing: [MainWindowController] = []

  private let confirmer: CloseConfirmer

  /// The visible frame decides where a cascade wraps. It defaults to the window's screen. The
  /// confirmer asks before a quit that would end something running.
  public init(
    visibleFrame: @escaping @MainActor (NSWindow) -> NSRect? = { window in
      (window.screen ?? NSScreen.main)?.visibleFrame
    },
    confirmer: @escaping CloseConfirmer = CloseDialog.present,
    makeController: @escaping Factory
  ) {
    self.visibleFrame = visibleFrame
    self.confirmer = confirmer
    self.makeController = makeController
  }

  /// Everything running in any window, hidden closed panes included. Quitting ends all of it.
  public var runningTabLabels: [String] {
    controllers.flatMap { $0.runningTabLabels }
  }

  /// Asks before a quit that would end something running. Returns true when the app may quit.
  public func shouldQuit() async -> Bool {
    let labels = runningTabLabels

    guard !labels.isEmpty else { return true }

    let request = CloseConfirmation(
      title: "Quit uniterm?",
      detail: "Quitting ends everything that is running in every window.", labels: labels,
      confirmTitle: "Quit", cancelTitle: "Cancel")

    return await confirmer(request, activeController?.window)
  }

  /// Ends the hidden closed panes of every window. A quit calls it, so no process outlives the app
  /// as a pane the user cannot see.
  public func hangUpHiddenPanes() {
    for controller in controllers {
      controller.hangUpHiddenPanes()
    }
  }

  /// The identifier of the nth window ever opened. The first keeps the plain name. A number is
  /// never reused, so two open windows never share an identifier.
  static func identifier(forSerial serial: Int) -> String {
    serial == 1 ? "main-window" : "main-window-\(serial)"
  }

  /// The window that menu actions and new windows follow: the key window, else the main one, else
  /// the one opened last.
  public var activeController: MainWindowController? {
    controllers.last { $0.window?.isKeyWindow == true }
      ?? controllers.last { $0.window?.isMainWindow == true }
      ?? controllers.last
  }

  /// Opens a window, shows it, and returns its controller. It cascades from the active window, and
  /// the first window is centered. When the factory throws, nothing opens and no number is used.
  @discardableResult
  public func open() throws -> MainWindowController {
    let anchor = activeController?.window

    let number = serial + 1
    let controller = try makeController(Self.identifier(forSerial: number))
    serial = number

    controller.onClose = { [weak self] controller in
      self?.windowDidClose(controller)
    }
    controllers.append(controller)

    if let anchor, let window = controller.window {
      let corner = WindowCascade.topLeft(
        after: anchor.frame, size: window.frame.size, in: visibleFrame(anchor))
      window.setFrameTopLeftPoint(corner)
    }

    for message in held {
      controller.statusCenter.post(level: message.level, source: message.source, text: message.text)
    }
    held.removeAll()

    controller.showWindow(nil)
    return controller
  }

  /// Opens a window when no main window is open, and says whether it did. A Dock click calls it.
  /// Only the set's own windows count, so the Settings window never stands in for a main one.
  public func openIfNone() throws -> Bool {
    guard controllers.isEmpty else { return false }

    try open()
    return true
  }

  /// Posts to the active window. With no window open, the message waits and goes to the next
  /// window that opens, so an app-level error is never lost.
  public func post(level: StatusLevel, source: StatusSource, text: String) {
    guard let controller = activeController else {
      held.append((level, source, text))
      return
    }

    controller.statusCenter.post(level: level, source: source, text: text)
  }

  private func windowDidClose(_ controller: MainWindowController) {
    controllers.removeAll { $0 === controller }
    closing.append(controller)

    Task { @MainActor [weak self] in
      self?.closing.removeAll { $0 === controller }
    }
  }
}

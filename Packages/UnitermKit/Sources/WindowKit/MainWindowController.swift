import AppKit
import AppletKit
import StatusKit
import Theme

/// Makes the applet that a new pane runs. The window controller owns what it returns.
public typealias AppletFactory = @MainActor () -> any Applet

/// Hosts one window with a full-size content view. Content extends under the title bar, and the
/// standard traffic lights stay. The content area holds one pane that runs one applet.
@MainActor
public final class MainWindowController: NSWindowController, NSWindowDelegate, AppletHost {
  /// The window's message queue. Anything in the window may post to it.
  public let statusCenter: StatusCenter

  private let contentController: MainContentViewController
  private let appearance: AppearanceController
  private let applet: any Applet
  private let paneID: UInt64 = 1
  private var appearanceToken: UUID?
  private var statusToken: UUID?
  private var paneClosed = false

  public init(
    appearance: AppearanceController, statusCenter: StatusCenter = StatusCenter(),
    makeApplet: AppletFactory
  ) {
    self.appearance = appearance
    self.statusCenter = statusCenter

    let applet = makeApplet()
    self.applet = applet
    contentController = MainContentViewController(paneView: applet.view)

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false)
    window.title = "uniterm"
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.minSize = NSSize(width: 480, height: 320)
    window.isReleasedWhenClosed = false
    window.setAccessibilityIdentifier("main-window")
    window.contentViewController = contentController
    window.setContentSize(NSSize(width: 960, height: 640))
    window.center()

    super.init(window: window)

    window.delegate = self
    applet.host = self

    appearanceToken = appearance.addObserver { [weak self] palette in
      self?.apply(palette)
    }

    statusToken = statusCenter.addObserver { [weak self] in
      guard let self else { return }

      contentController.showStatus(self.statusCenter.display)
    }
  }

  isolated deinit {
    if let appearanceToken {
      appearance.removeObserver(appearanceToken)
    }

    if let statusToken {
      statusCenter.removeObserver(statusToken)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  public override func showWindow(_ sender: Any?) {
    super.showWindow(sender)

    applet.start()
    applet.focus()
  }

  private func apply(_ palette: ThemePalette) {
    window?.backgroundColor = palette[.base].nsColor
    contentController.apply(palette)
  }

  // MARK: Menu actions

  @objc public func newTab(_ sender: Any?) {
    statusCenter.post(level: .info, source: .uniterm, text: "Tabs are not available yet.")
  }

  @objc public func splitPane(_ sender: Any?) {
    statusCenter.post(level: .info, source: .uniterm, text: "Splits are not available yet.")
  }

  @objc public func undoClosePane(_ sender: Any?) {
    statusCenter.post(level: .info, source: .uniterm, text: "There is no closed pane to undo yet.")
  }

  /// Closes the pane. The pane is the only one in the window, so the window closes too.
  @objc public func closePane(_ sender: Any?) {
    window?.performClose(sender)
  }

  // MARK: Window

  public func windowWillClose(_ notification: Notification) {
    guard !paneClosed else { return }

    paneClosed = true
    applet.close()
  }

  // MARK: Applet host

  public func applet(_ applet: any Applet, post level: StatusLevel, text: String) {
    statusCenter.post(
      level: level, source: .pane(id: paneID, name: applet.title), text: text)
  }

  public func appletDidExit(_ applet: any Applet) {
    window?.close()
  }

  public func appletDidChange(_ applet: any Applet) {}

  public func applet(_ applet: any Applet, confirm request: AppletConfirmation) async -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = request.title
    alert.informativeText = "Pane \u{201C}\(applet.title)\u{201D}. \(request.detail)"
    alert.addButton(withTitle: request.cancelTitle)
    alert.addButton(withTitle: request.confirmTitle)
    alert.buttons[0].keyEquivalent = "\r"
    alert.buttons[1].keyEquivalent = ""

    let response: NSApplication.ModalResponse
    if let window, window.isVisible {
      response = await alert.beginSheetModal(for: window)
    } else {
      response = alert.runModal()
    }

    return response == .alertSecondButtonReturn
  }
}

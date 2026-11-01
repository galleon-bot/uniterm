import AppKit
import AppletKit
import PaneModel
import Preferences
import StatusKit
import Theme

/// Makes the applet that a new pane runs. It throws when it cannot start the choice. The window
/// controller owns what it returns.
public typealias AppletFactory = @MainActor (AppletChoice) throws -> any Applet

/// Hosts one window with a full-size content view. Content extends under the title bar, and the
/// standard traffic lights stay. The content area holds a tree of panes, and each pane runs one
/// applet.
@MainActor
public final class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation,
  AppletHost
{
  /// The window's message queue. Anything in the window may post to it.
  public let statusCenter: StatusCenter

  let contentController: MainContentViewController
  let paneArea: PaneAreaView
  private let appearance: AppearanceController
  private let placement: StatusBarPlacement
  private let makeApplet: AppletFactory
  private var appearanceToken: UUID?
  private var statusToken: UUID?
  private var started = Set<ObjectIdentifier>()
  private var panesClosed = false
  private var historyVisible = false

  /// The settings store supplies the status bar position, which is global to every window.
  public init(
    appearance: AppearanceController, settings: SettingsStore,
    statusCenter: StatusCenter = StatusCenter(), makeApplet: @escaping AppletFactory
  ) throws {
    self.appearance = appearance
    self.statusCenter = statusCenter
    self.makeApplet = makeApplet
    placement = StatusBarPlacement(store: settings, statusCenter: statusCenter)

    paneArea = PaneAreaView(firstApplet: try makeApplet(.terminalShell))
    contentController = MainContentViewController(
      paneView: paneArea, statusBarEdge: DockEdge(placement.position))

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false)
    window.title = "uniterm"
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isReleasedWhenClosed = false
    window.setAccessibilityIdentifier("main-window")
    window.contentViewController = contentController
    window.setContentSize(NSSize(width: 960, height: 640))
    window.center()

    super.init(window: window)

    window.delegate = self
    for applet in paneArea.applets { applet.host = self }

    paneArea.onTreeChange = { [weak self] in self?.updateMinimumSize() }
    paneArea.onFocusChange = { [weak self] in self?.refreshStatusBar() }
    contentController.onLayout = { [weak self] in self?.updateMinimumSize() }
    contentController.statusBar.onActivate = { [weak self] in self?.toggleMessageHistory(nil) }
    contentController.statusBar.onDismiss = { [weak self] in self?.dismissMessage(nil) }
    placement.onChange = { [weak self] position in
      self?.contentController.move(.statusBar, to: DockEdge(position))
    }
    updateMinimumSize()

    appearanceToken = appearance.addObserver { [weak self] palette in
      self?.apply(palette)
    }

    statusToken = statusCenter.addObserver { [weak self] in
      self?.statusDidChange()
    }

    refreshStatusBar()
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

    contentController.view.layoutSubtreeIfNeeded()
    startPendingApplets()
    paneArea.focus(paneArea.focusedPane)
  }

  private func apply(_ palette: ThemePalette) {
    window?.backgroundColor = palette[.base].nsColor
    contentController.apply(palette)
    paneArea.apply(palette)
  }

  // MARK: Status bar

  /// The segments the bar shows now. The window owns the message area and the unseen-error
  /// indicator. The applet of the focused pane fills the rest. The pane model decides which pane
  /// that is, not the first responder, so the segments stay put while the keyboard is in the
  /// Settings window or a sheet.
  var statusBarSegments: [BarSegment] {
    StatusBarContent.segments(
      display: statusCenter.display, hasUnseenError: statusCenter.hasUnseenError,
      applet: paneArea.applet(for: paneArea.focusedPane)?.segments ?? [])
  }

  private func refreshStatusBar() {
    contentController.statusBar.show(statusBarSegments)
  }

  private func statusDidChange() {
    if historyVisible, statusCenter.hasUnseenError {
      statusCenter.markHistorySeen()
      return
    }

    refreshStatusBar()

    if historyVisible {
      contentController.history.show(statusCenter.history)
    }
  }

  /// Opens or closes the history. Opening it marks the errors as seen.
  func setHistoryVisible(_ visible: Bool) {
    guard visible != historyVisible else { return }

    historyVisible = visible
    contentController.setHistoryVisible(visible)

    if visible {
      contentController.history.show(statusCenter.history)
      statusCenter.markHistorySeen()
    }
  }

  var isHistoryVisible: Bool { historyVisible }

  /// The window never shrinks below what the tree needs. The tree's minimum is for the pane area
  /// alone, so the title bar and the docked regions add to it.
  private func updateMinimumSize() {
    guard let window else { return }

    let tree = paneArea.minimumSize
    let minimum = NSSize(
      width: tree.width, height: tree.height + contentController.chromeHeight)

    if window.contentMinSize != minimum {
      window.contentMinSize = minimum
    }
  }

  private func startPendingApplets() {
    for applet in paneArea.applets where started.insert(ObjectIdentifier(applet)).inserted {
      applet.start()
    }
  }

  // MARK: Panes

  /// The panes in reading order. Tests and the UI read it.
  var paneIDs: [NodeID] { paneArea.tree.paneIDs }

  var focusedPane: NodeID { paneArea.focusedPane }

  /// Splits the focused pane and starts the chosen applet in the new one. Returns nil when the
  /// pane is too small, or the applet could not start. Either way the status bar says why.
  @discardableResult
  func openPane(_ choice: AppletChoice, axis: Axis) -> NodeID? {
    contentController.view.layoutSubtreeIfNeeded()

    let applet: any Applet
    do {
      applet = try makeApplet(choice)
    } catch {
      statusCenter.post(
        level: .error, source: .uniterm,
        text: "The pane did not open: \(error.localizedDescription)"
      )
      return nil
    }

    applet.host = self

    let created: NodeID
    do {
      created = try paneArea.split(axis, adding: applet)
    } catch {
      applet.close()
      postNoRoom()
      return nil
    }

    startPendingApplets()
    paneArea.focus(created)
    return created
  }

  private func postNoRoom() {
    statusCenter.post(
      level: .warning, source: .uniterm, text: "There is not enough room to split this pane.")
  }

  /// A sheet, such as the picker or a clipboard question, holds the window's attention. Pane
  /// actions wait until it is answered. Cmd-W does not cancel a sheet, and Escape does.
  private var paneActionsEnabled: Bool {
    window?.attachedSheet == nil
  }

  public func validateMenuItem(_ item: NSMenuItem) -> Bool {
    switch item.action {
    case #selector(splitRight(_:)), #selector(splitDown(_:)),
      #selector(focusNextPane(_:)), #selector(focusPreviousPane(_:)),
      #selector(focusPaneLeft(_:)), #selector(focusPaneRight(_:)),
      #selector(focusPaneUp(_:)), #selector(focusPaneDown(_:)),
      #selector(closePane(_:)):
      return paneActionsEnabled

    case #selector(toggleMessageHistory(_:)):
      item.title = historyVisible ? "Hide Message History" : "Show Message History"
      return true

    case #selector(dismissMessage(_:)):
      return statusCenter.display?.message.level == .error

    default:
      return true
    }
  }

  private func requestSplit(_ axis: Axis) {
    guard let window, paneActionsEnabled else { return }

    contentController.view.layoutSubtreeIfNeeded()

    guard paneArea.canSplit(axis) else {
      postNoRoom()
      return
    }

    NewPaneSheet.present(on: window) { [weak self] choice in
      self?.openPane(choice, axis: axis)
    }
  }

  /// Closes one pane. Its space goes to its neighbors. The last pane closes the window, through
  /// `performClose` when the user asked, and straight away when its applet ended on its own.
  private func closePane(_ pane: NodeID, appletEnded: Bool) {
    do {
      guard let removed = try paneArea.remove(pane) else {
        if appletEnded {
          window?.close()
        } else {
          window?.performClose(nil)
        }

        return
      }

      started.remove(ObjectIdentifier(removed.applet))
      removed.applet.close()
      statusCenter.paneClosed(id: pane.rawValue)

      if let next = removed.refocus {
        paneArea.focus(next)
      }
    } catch {
      // The pane is already gone, as when its applet exits twice. There is nothing left to close.
      return
    }
  }

  // MARK: Menu actions

  @objc public func newTab(_ sender: Any?) {
    statusCenter.post(level: .info, source: .uniterm, text: "Tabs are not available yet.")
  }

  @objc public func splitRight(_ sender: Any?) {
    requestSplit(.row)
  }

  @objc public func splitDown(_ sender: Any?) {
    requestSplit(.column)
  }

  @objc public func focusNextPane(_ sender: Any?) {
    guard paneActionsEnabled else { return }

    paneArea.focusNext()
  }

  @objc public func focusPreviousPane(_ sender: Any?) {
    guard paneActionsEnabled else { return }

    paneArea.focusPrevious()
  }

  @objc public func focusPaneLeft(_ sender: Any?) {
    guard paneActionsEnabled else { return }

    paneArea.focusNeighbor(.left)
  }

  @objc public func focusPaneRight(_ sender: Any?) {
    guard paneActionsEnabled else { return }

    paneArea.focusNeighbor(.right)
  }

  @objc public func focusPaneUp(_ sender: Any?) {
    guard paneActionsEnabled else { return }

    paneArea.focusNeighbor(.up)
  }

  @objc public func focusPaneDown(_ sender: Any?) {
    guard paneActionsEnabled else { return }

    paneArea.focusNeighbor(.down)
  }

  /// Opens the message history over the pane area, or closes it. The status bar's click does the
  /// same.
  @objc public func toggleMessageHistory(_ sender: Any?) {
    setHistoryVisible(!historyVisible)
  }

  /// Clears the error on the bar. An error stays until a newer message replaces it or the user
  /// does this. Other messages clear themselves, so there is nothing to dismiss.
  @objc public func dismissMessage(_ sender: Any?) {
    statusCenter.dismissCurrent()
  }

  @objc public func undoClosePane(_ sender: Any?) {
    statusCenter.post(level: .info, source: .uniterm, text: "There is no closed pane to undo yet.")
  }

  /// Closes the focused pane. With one pane left, the window closes too.
  @objc public func closePane(_ sender: Any?) {
    guard paneActionsEnabled else { return }

    closePane(paneArea.focusedPane, appletEnded: false)
  }

  // MARK: Window

  public func windowWillClose(_ notification: Notification) {
    guard !panesClosed else { return }

    panesClosed = true
    for applet in paneArea.applets { applet.close() }
  }

  // MARK: Applet host

  public func applet(_ applet: any Applet, post level: StatusLevel, text: String) {
    let id = paneArea.paneID(for: applet)?.rawValue ?? 0
    statusCenter.post(level: level, source: .pane(id: id, name: applet.title), text: text)
  }

  public func appletDidExit(_ applet: any Applet) {
    guard let pane = paneArea.paneID(for: applet) else { return }

    closePane(pane, appletEnded: true)
  }

  /// Only the focused pane's applet shows in the bar, so a change in any other applet is not
  /// the bar's business until that pane takes focus.
  public func appletDidChange(_ applet: any Applet) {
    guard applet === paneArea.applet(for: paneArea.focusedPane) else { return }

    refreshStatusBar()
  }

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

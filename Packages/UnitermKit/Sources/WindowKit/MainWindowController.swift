import AppKit
import AppletKit
import LayoutKit
import PaneModel
import Preferences
import StatusKit
import Theme

/// Makes the applet that a new pane runs. The directory is where the new pane starts, taken from
/// the pane it was opened from. It is nil for the first pane of a window, and the factory picks
/// the start then. The factory throws when it cannot start the choice. The window controller owns
/// what it returns.
public typealias AppletFactory = @MainActor (AppletChoice, String?) throws -> any Applet

/// Makes an applet from the description of a closed pane. It throws when the description is
/// unknown, newer than this build, or unreadable. The applet must start nothing until the window
/// starts it, and a restored program waits for the user to run it.
public typealias AppletRestorer = @MainActor (AppletDescription) throws -> any Applet

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
  private let restoreApplet: AppletRestorer
  private var appearanceToken: UUID?
  private var statusToken: UUID?
  private var started = Set<ObjectIdentifier>()
  private var panesClosed = false
  private var historyVisible = false

  /// The window's closed panes, as descriptions. No closed applet is kept alive.
  private(set) var ledger: CloseUndoLedger

  /// Asks the user before something is ended that undo cannot bring back. Tests replace it.
  var confirmer: CloseConfirmer = CloseDialog.present

  /// The question the window is asking now, if any. A second question is not stacked on it.
  private(set) var pendingGuard: Task<Void, Never>?

  /// Applets that ended on their own and are still in the tree, such as a last pane left behind by
  /// a cancelled window question. Closing one adds no undo entry.
  private var exitedApplets = Set<ObjectIdentifier>()

  /// Runs once, when the window closes. The set of windows uses it to let go of the controller.
  var onClose: ((MainWindowController) -> Void)?

  /// The description of each pane as of the last snapshot of the window.
  private var savedDescriptions: [NodeID: AppletDescription] = [:]

  /// Runs when something a saved layout holds changes: the pane tree, the focus, the window's frame,
  /// or an applet's description.
  var onLayoutChange: (() -> Void)?

  /// The visible area of the screen the window is on. A window never asks for more room than that.
  /// Tests replace it.
  var visibleFrameProvider: @MainActor (NSWindow) -> NSRect? = { window in
    (window.screen ?? NSScreen.main)?.visibleFrame
  }

  /// The settings store supplies the status bar position, which is global to every window. The
  /// identifier names the window to accessibility, so it must differ between open windows.
  ///
  /// The undo policy sets how many closes the window remembers.
  ///
  /// A restored window takes its pane tree and its applets from the saved layout, and `makeApplet`
  /// is not called for the first pane. Otherwise the first pane starts in `directory`.
  public init(
    appearance: AppearanceController, settings: SettingsStore,
    statusCenter: StatusCenter = StatusCenter(),
    identifier: String = "main-window",
    undoPolicy: CloseUndoPolicy = .standard,
    startingIn directory: String? = nil,
    restoring restored: RestoredWindow? = nil,
    restoreApplet: @escaping AppletRestorer = { _ in
      throw AppletRestoreError.unsupported("this window cannot reopen a closed pane")
    },
    makeApplet: @escaping AppletFactory
  ) throws {
    self.appearance = appearance
    self.statusCenter = statusCenter
    self.makeApplet = makeApplet
    self.restoreApplet = restoreApplet
    ledger = CloseUndoLedger(policy: undoPolicy)
    placement = StatusBarPlacement(store: settings, statusCenter: statusCenter)

    let panes = try restored.map { try PaneRestoration.restore($0, restorer: restoreApplet) }

    if let panes {
      paneArea = PaneAreaView(restoring: panes.tree, applets: panes.applets, focus: panes.focus)
    } else {
      paneArea = PaneAreaView(firstApplet: try makeApplet(.terminalShell, directory))
    }

    contentController = MainContentViewController(
      paneView: paneArea, statusBarEdge: DockEdge(placement.position))

    let window = MainWindow(
      contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false)
    window.title = "uniterm"
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isReleasedWhenClosed = false
    window.isRestorable = false
    window.setAccessibilityIdentifier(identifier)
    window.contentViewController = contentController
    window.setContentSize(NSSize(width: 960, height: 640))
    window.center()

    super.init(window: window)

    window.delegate = self
    for applet in paneArea.applets { adopt(applet) }

    paneArea.onTreeChange = { [weak self] in self?.updateMinimumSize() }
    paneArea.onLayoutChange = { [weak self] in self?.onLayoutChange?() }
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

    if let panes, panes.placeholders > 0 {
      let noun = panes.placeholders == 1 ? "pane" : "panes"
      statusCenter.post(
        level: .warning, source: .uniterm,
        text: "\(panes.placeholders) saved \(noun) could not be restored and kept as they were.")
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

  func refreshMinimumSize() {
    updateMinimumSize()
  }

  /// The window never shrinks below what the tree needs. The tree's minimum is for the pane area
  /// alone, so the title bar and the docked regions add to it.
  private func updateMinimumSize() {
    guard let window else { return }

    let tree = paneArea.minimumSize
    var minimum = NSSize(
      width: tree.width, height: tree.height + contentController.chromeHeight)

    // A tree that needs more than the screen offers still opens. The layout holds each pane at its
    // minimum and overflows, and the user closes panes or moves focus by keyboard.
    if let visible = visibleFrameProvider(window) {
      let room = window.contentRect(forFrameRect: visible).size
      minimum = NSSize(
        width: min(minimum.width, room.width), height: min(minimum.height, room.height))
    }

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

  /// Makes the window the applet's host. A launcher also learns how to open its choice.
  private func adopt(_ applet: any Applet) {
    applet.host = self

    if let launcher = applet as? LauncherApplet {
      launcher.onChoose = { [weak self, weak launcher] choice in
        guard let self, let launcher else { return }

        try replace(launcher, with: choice)
      }
    }
  }

  /// The directory the focused pane's applet reports, for a pane opened from it.
  var focusedDirectory: String? {
    paneArea.applet(for: focusedPane)?.currentDirectory
  }

  /// Splits the focused pane and starts the chosen applet in the new one, in the directory the
  /// focused pane reports. Returns nil when the pane is too small, or the applet could not start.
  /// Either way the status bar says why.
  @discardableResult
  func openPane(_ choice: AppletChoice, axis: Axis) -> NodeID? {
    contentController.view.layoutSubtreeIfNeeded()

    let applet: any Applet
    do {
      applet = try makeApplet(choice, focusedDirectory)
    } catch {
      statusCenter.post(
        level: .error, source: .uniterm,
        text: "The pane did not open: \(error.localizedDescription)"
      )
      return nil
    }

    return place(applet, axis: axis)
  }

  /// Splits the focused pane and puts a launcher in the new one, which takes the keyboard. The
  /// launcher remembers the directory the focused pane reports and starts what it opens there.
  @discardableResult
  func openLauncher(axis: Axis) -> NodeID? {
    contentController.view.layoutSubtreeIfNeeded()

    return place(LauncherApplet(directory: focusedDirectory), axis: axis)
  }

  private func place(_ applet: any Applet, axis: Axis) -> NodeID? {
    adopt(applet)

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

  /// Runs the choice in the launcher's pane. The pane keeps its ID and its place, and the launcher
  /// closes. It throws before anything changes when the choice cannot start, so the launcher stays
  /// and shows the reason.
  private func replace(_ launcher: LauncherApplet, with choice: AppletChoice) throws {
    guard let pane = paneArea.paneID(for: launcher) else { return }

    let applet = try makeApplet(choice, launcher.currentDirectory)
    adopt(applet)

    guard let replaced = paneArea.replace(pane, with: applet) else {
      applet.close()
      return
    }

    started.remove(ObjectIdentifier(replaced))
    replaced.close()

    startPendingApplets()
    paneArea.focus(pane)
    refreshStatusBar()
  }

  private func postNoRoom() {
    statusCenter.post(
      level: .warning, source: .uniterm, text: "There is not enough room to split this pane.")
  }

  /// A sheet, such as a close question or a clipboard question, holds the window's attention. Pane
  /// actions wait until it is answered. Cmd-W does not cancel a sheet, and Escape does.
  private var paneActionsEnabled: Bool {
    window?.attachedSheet == nil
  }

  public func validateMenuItem(_ item: NSMenuItem) -> Bool {
    switch item.action {
    case #selector(splitRight(_:)), #selector(splitDown(_:)),
      #selector(focusNextPane(_:)), #selector(focusPreviousPane(_:)),
      #selector(focusPaneLeft(_:)), #selector(focusPaneRight(_:)),
      #selector(focusPaneUp(_:)), #selector(focusPaneDown(_:)):
      return paneActionsEnabled

    case #selector(closePane(_:)):
      item.title = (focusedTabbedApplet?.tabCount ?? 1) > 1 ? "Close Tab" : "Close Pane"
      return paneActionsEnabled

    case #selector(MainWindow.undoCloseOrEdit(_:)):
      item.title = "Undo Close Pane"
      return paneActionsEnabled

    case #selector(newTab(_:)):
      return paneActionsEnabled && focusedTabbedApplet?.canOpenTab == true

    case #selector(selectNextTab(_:)), #selector(selectPreviousTab(_:)),
      #selector(selectTabByNumber(_:)):
      return paneActionsEnabled && (focusedTabbedApplet?.tabCount ?? 1) > 1

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
    guard paneActionsEnabled else { return }

    contentController.view.layoutSubtreeIfNeeded()

    guard paneArea.canSplit(axis) else {
      postNoRoom()
      return
    }

    openLauncher(axis: axis)
  }

  // MARK: Closing panes

  /// Closes one pane. Its space goes to its neighbors. The last pane closes the window.
  ///
  /// A pane the user closes ends its applet at once, and its description goes on the undo stack. A
  /// pane that is running something asks first. A pane whose applet ended on its own has nothing to
  /// undo, and neither has a launcher.
  private func closePane(_ pane: NodeID, appletEnded: Bool) {
    guard let applet = paneArea.applet(for: pane) else { return }

    guard paneArea.paneCount > 1 else {
      closeLastPane()
      return
    }

    if appletEnded || exitedApplets.contains(ObjectIdentifier(applet)) || applet is LauncherApplet {
      discard(pane)
    } else if applet.isRunningSomething {
      askBeforeClosing(pane, applet: applet)
    } else {
      describeAndClose(pane)
    }
  }

  private func askBeforeClosing(_ pane: NodeID, applet: any Applet) {
    let request = CloseConfirmation(
      title: "Close this pane?",
      detail:
        "Closing this pane ends what is running in it. Undo reopens the pane in the same place, but not the running session.",
      labels: applet.runningLabels, confirmTitle: "Close Pane", cancelTitle: "Cancel")

    ask(request) { [weak self] in
      guard let self, paneArea.applet(for: pane) === applet else { return }

      if paneArea.paneCount > 1 {
        describeAndClose(pane)
      } else {
        window?.close()
      }
    }
  }

  /// Ends the pane's applet at once and puts its description on the undo stack.
  private func describeAndClose(_ pane: NodeID) {
    guard let applet = paneArea.applet(for: pane), let removed = try? paneArea.remove(pane)
    else { return }

    let closed = ClosedPane(
      placement: removed.placement, description: applet.describe(), title: applet.title)

    started.remove(ObjectIdentifier(applet))
    applet.close()
    statusCenter.paneClosed(id: pane.rawValue)

    if let next = removed.refocus {
      paneArea.focus(next)
    }

    ledger.push(closed)
  }

  /// Closes a pane whose applet ended on its own. Nothing is kept for undo.
  private func discard(_ pane: NodeID) {
    guard let applet = paneArea.applet(for: pane), let removed = try? paneArea.remove(pane)
    else { return }

    started.remove(ObjectIdentifier(applet))
    exitedApplets.remove(ObjectIdentifier(applet))
    applet.close()
    statusCenter.paneClosed(id: pane.rawValue)

    if let next = removed.refocus {
      paneArea.focus(next)
    }
  }

  /// What is running in this window. Closing the window or quitting ends all of it.
  public var runningTabLabels: [String] {
    paneArea.applets.flatMap { $0.runningLabels }
  }

  /// The last pane closes the window. When something is running in it, the user is asked first,
  /// and Cancel keeps the window. A pane whose applet ended while the question is open is not
  /// asked about again. It stays after a Cancel, and closing it then needs no question.
  private func closeLastPane() {
    guard pendingGuard == nil else { return }

    let labels = runningTabLabels

    guard !labels.isEmpty else {
      window?.close()
      return
    }

    askToCloseWindow(labels: labels)
  }

  private func askToCloseWindow(labels: [String]) {
    let request = CloseConfirmation(
      title: "Close this window?",
      detail: "Closing the window ends everything that is running in it.", labels: labels,
      confirmTitle: "Close Window", cancelTitle: "Cancel")

    ask(request) { [weak self] in
      self?.window?.close()
    }
  }

  /// Shows a question and runs `onConfirm` when the user agrees. Declining does nothing. A second
  /// question is dropped while the first is open.
  private func ask(_ request: CloseConfirmation, onConfirm: @escaping @MainActor () -> Void) {
    guard pendingGuard == nil else { return }

    pendingGuard = Task { @MainActor [weak self] in
      guard let self else { return }

      let confirmed = await confirmer(request, window)
      pendingGuard = nil

      if confirmed {
        onConfirm()
      }
    }
  }

  /// Opens a pane from a closed pane's description, in the same place with the same kind of applet.
  /// The pane gets a new ID, and the applet starts fresh. A description this build cannot restore
  /// opens as a placeholder, which keeps its bytes. The entry stays on the stack when the pane does
  /// not fit.
  private func reopen(_ closed: ClosedPane) {
    let restored = PaneRestoration.applet(for: closed.description, restorer: restoreApplet)
    let applet = restored.applet

    adopt(applet)

    let id: NodeID
    do {
      id = try paneArea.insert(applet, at: closed.placement)
    } catch {
      applet.close()
      postNoRoom(to: "reopen the pane")
      return
    }

    ledger.removeNewest()
    startPendingApplets()
    paneArea.focus(id)

    if restored.isPlaceholder {
      statusCenter.post(
        level: .warning, source: .uniterm,
        text:
          "The pane \u{201C}\(closed.title)\u{201D} could not be restored. It is kept as it was.")
    }
  }

  private func postNoRoom(to action: String) {
    statusCenter.post(
      level: .warning, source: .uniterm, text: "There is not enough room to \(action).")
  }

  // MARK: Menu actions

  /// The focused pane's applet when it holds tabs.
  private var focusedTabbedApplet: (any TabbedApplet)? {
    paneArea.applet(for: paneArea.focusedPane) as? any TabbedApplet
  }

  /// Opens a tab in the focused pane's applet. A program-mode terminal has one tab, so the item is
  /// disabled there.
  @objc public func newTab(_ sender: Any?) {
    guard paneActionsEnabled, let applet = focusedTabbedApplet, applet.canOpenTab else { return }

    applet.openTab()
  }

  @objc public func selectNextTab(_ sender: Any?) {
    stepTab(by: 1)
  }

  @objc public func selectPreviousTab(_ sender: Any?) {
    stepTab(by: -1)
  }

  /// Selects the tab numbered by the sender's tag, counting from 1. Tag 9 selects the last tab,
  /// as Terminal and Ghostty do.
  @objc public func selectTabByNumber(_ sender: Any?) {
    guard paneActionsEnabled, let applet = focusedTabbedApplet,
      let number = (sender as? NSMenuItem)?.tag, number > 0
    else { return }

    applet.selectTab(at: number == 9 ? applet.tabCount - 1 : number - 1)
  }

  private func stepTab(by step: Int) {
    guard paneActionsEnabled, let applet = focusedTabbedApplet, applet.tabCount > 1 else { return }

    let count = applet.tabCount
    applet.selectTab(at: (applet.selectedTabIndex + step + count) % count)
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

  /// Reopens the pane that closed last from its description, in its former place, with a new ID.
  ///
  /// The window calls this for the standard undo action, except while a text control is being
  /// edited. Then Cmd-Z undoes the edit and never a pane close.
  @objc public func undoClosePane(_ sender: Any?) {
    guard paneActionsEnabled else { return }

    guard let closed = ledger.newest else {
      statusCenter.post(level: .info, source: .uniterm, text: "There is no closed pane to undo.")
      return
    }

    reopen(closed)
  }

  /// Closes the focused pane's selected tab when its applet has several. Otherwise it closes the
  /// pane, and with one pane left the window closes too.
  ///
  /// A tab running something asks first, and the applet does the asking. A pane close asks when any
  /// of its tabs is running something. A close that ends the window asks when anything in the
  /// window is running.
  @objc public func closePane(_ sender: Any?) {
    guard paneActionsEnabled else { return }

    if let applet = focusedTabbedApplet, applet.tabCount > 1 {
      Task { @MainActor in _ = await applet.closeSelectedTab() }
      return
    }

    closePane(paneArea.focusedPane, appletEnded: false)
  }

  // MARK: Saved layout

  /// The window as a saved layout holds it. The undo stack is not part of it. The IDs of closed
  /// panes stay below the layout's high-water mark.
  ///
  /// A pane with no applet cannot happen while the window is consistent. If it did, the pane is
  /// left out, so the rest of the layout still saves. A window with no pane left is not saved.
  func savedWindow() -> SavedWindow? {
    guard let window else { return nil }

    var described: [NodeID: AppletDescription] = [:]

    guard let tree = savedNode(paneArea.tree.root, described: &described) else { return nil }

    savedDescriptions = described

    return SavedWindow(
      frame: window.frame, screen: window.screen?.frame, tree: tree,
      focusedPane: paneArea.focusedPane, highWaterMark: paneArea.tree.highWaterMark)
  }

  private func savedNode(_ node: Node, described: inout [NodeID: AppletDescription]) -> SavedNode? {
    switch node {
    case .pane(let pane):
      guard let applet = paneArea.applet(for: pane.id) else { return nil }

      let description = applet.describe()
      described[pane.id] = description
      return .pane(id: pane.id, applet: description)

    case .split(let split):
      var children: [SavedChild] = []

      for child in split.children {
        if let saved = savedNode(child.node, described: &described) {
          children.append(SavedChild(node: saved, weight: child.weight))
        }
      }

      switch children.count {
      case 0: return nil
      case 1: return children[0].node
      default: return .split(id: split.id, axis: split.axis, children: children)
      }
    }
  }

  /// A title or segment change that leaves the saved description the same, such as a spinner in a
  /// title, is not a layout change. Only a description that differs from the last saved one is.
  private func notifyLayoutIfDescriptionChanged(_ applet: any Applet) {
    guard let pane = paneArea.paneID(for: applet),
      let saved = savedDescriptions[pane], saved == applet.describe()
    else {
      onLayoutChange?()
      return
    }
  }

  // MARK: Window

  /// The red button and Cmd-Q on the last window end here. When something is running in the window,
  /// the sheet asks and the close waits for the answer.
  public func windowShouldClose(_ sender: NSWindow) -> Bool {
    let labels = runningTabLabels

    guard !labels.isEmpty else { return true }

    askToCloseWindow(labels: labels)
    return false
  }

  public func windowDidMove(_ notification: Notification) {
    onLayoutChange?()
  }

  public func windowDidResize(_ notification: Notification) {
    onLayoutChange?()
  }

  /// Closing the window ends every applet in it and lets go of the undo stack. Undoing a closed
  /// window is out of scope.
  public func windowWillClose(_ notification: Notification) {
    guard !panesClosed else { return }

    panesClosed = true

    for applet in paneArea.applets { applet.close() }

    ledger.removeAll()

    let handler = onClose
    onClose = nil
    handler?(self)
  }

  // MARK: Applet host

  public func applet(_ applet: any Applet, post level: StatusLevel, text: String) {
    // An applet may keep bounded, visible work after close and still post. ID 0 never matches a
    // live pane.
    let id = paneArea.paneID(for: applet)?.rawValue ?? 0
    statusCenter.post(level: level, source: .pane(id: id, name: applet.title), text: text)
  }

  /// A pane whose applet ended closes, and keeps nothing for undo.
  public func appletDidExit(_ applet: any Applet) {
    if let pane = paneArea.paneID(for: applet) {
      exitedApplets.insert(ObjectIdentifier(applet))
      closePane(pane, appletEnded: true)
    }
  }

  /// Only the focused pane's applet shows in the bar, so a change in any other applet is not
  /// the bar's business until that pane takes focus.
  public func appletDidChange(_ applet: any Applet) {
    notifyLayoutIfDescriptionChanged(applet)

    guard applet === paneArea.applet(for: paneArea.focusedPane) else { return }

    refreshStatusBar()
  }

  public func applet(_ applet: any Applet, confirm request: AppletConfirmation) async -> Bool {
    let question = CloseConfirmation(
      title: request.title, detail: "Pane \u{201C}\(applet.title)\u{201D}. \(request.detail)",
      confirmTitle: request.confirmTitle, cancelTitle: request.cancelTitle)

    return await confirmer(question, window)
  }
}

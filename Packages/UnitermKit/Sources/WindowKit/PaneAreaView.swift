import AppKit
import AppletKit
import PaneModel
import Theme

/// Draws a pane tree. It owns the model, the pane views, and the dividers.
///
/// The model decides every frame. This view places a pane view in each frame and moves the
/// dividers the user drags. It never changes sizes itself.
@MainActor
final class PaneAreaView: NSView {
  private struct DividerKey: Hashable {
    let leading: NodeID
    let trailing: NodeID
  }

  private(set) var tree: PaneTree
  private(set) var focusedPane: NodeID

  /// Runs when the tree changes shape, so the window can follow the new minimum size.
  var onTreeChange: (() -> Void)?

  private var paneViews: [NodeID: PaneFrameView] = [:]
  private var dividerViews: [DividerKey: DividerView] = [:]
  private var palette: ThemePalette = .latte
  private var updateObserver: NSObjectProtocol?

  override var isFlipped: Bool { true }

  override var mouseDownCanMoveWindow: Bool { false }

  init(metrics: PaneMetrics = .standard, firstApplet: any Applet) {
    tree = PaneTree(metrics: metrics)
    focusedPane = tree.paneIDs[0]
    super.init(frame: .zero)

    install(firstApplet, as: focusedPane)
    paneViews[focusedPane]?.isFocused = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  isolated deinit {
    if let updateObserver {
      NotificationCenter.default.removeObserver(updateObserver)
    }
  }

  // MARK: Queries

  var minimumSize: NSSize { tree.minimumSize }

  var paneCount: Int { paneViews.count }

  /// Every applet, in reading order.
  var applets: [any Applet] {
    tree.paneIDs.compactMap { paneViews[$0]?.applet }
  }

  func applet(for pane: NodeID) -> (any Applet)? {
    paneViews[pane]?.applet
  }

  func paneView(for pane: NodeID) -> PaneFrameView? {
    paneViews[pane]
  }

  var dividers: [DividerView] {
    Array(dividerViews.values)
  }

  func paneID(for applet: any Applet) -> NodeID? {
    paneViews.first { $0.value.applet === applet }?.key
  }

  func canSplit(_ axis: Axis) -> Bool {
    tree.canSplit(focusedPane, axis: axis, in: bounds.size)
  }

  // MARK: Edits

  /// Splits the focused pane and puts `applet` in the new one. Throws when the pane is too small.
  /// The new pane takes focus.
  @discardableResult
  func split(_ axis: Axis, adding applet: any Applet) throws -> NodeID {
    let created = try tree.split(focusedPane, axis: axis, in: bounds.size)

    install(applet, as: created)
    changed()
    layoutSubtreeIfNeeded()
    return created
  }

  /// Removes a pane and gives its space to its neighbors. Returns nil for the last pane, which
  /// stays. The applet is returned for the caller to close.
  ///
  /// Focus moves only when the closed pane had it. Then `refocus` names the pane that takes over,
  /// and the caller gives it the keyboard. Closing any other pane leaves focus where it was.
  func remove(_ pane: NodeID) throws -> (applet: any Applet, refocus: NodeID?)? {
    guard let view = paneViews[pane] else { throw PaneTreeError.unknownPane(pane) }

    guard case .closed(let focus) = try tree.close(pane) else { return nil }

    let hadFocus = pane == focusedPane

    paneViews.removeValue(forKey: pane)
    view.removeFromSuperview()

    if hadFocus {
      focusedPane = focus
    }

    changed()
    layoutSubtreeIfNeeded()

    return (view.applet, hadFocus ? focus : nil)
  }

  private func install(_ applet: any Applet, as pane: NodeID) {
    let view = PaneFrameView(paneID: pane, applet: applet)
    view.apply(palette)
    paneViews[pane] = view
    addSubview(view)
  }

  private func changed() {
    refreshFocusMarks()
    needsLayout = true
    onTreeChange?()
  }

  // MARK: Focus

  /// Marks a pane focused and gives its applet the keyboard.
  func focus(_ pane: NodeID) {
    guard paneViews[pane] != nil else { return }

    setFocusedPane(pane)
    paneViews[pane]?.applet.focus()
  }

  func focusNext() {
    if let next = tree.nextPane(after: focusedPane) { focus(next) }
  }

  func focusPrevious() {
    if let previous = tree.previousPane(before: focusedPane) { focus(previous) }
  }

  func focusNeighbor(_ direction: Direction) {
    if let neighbor = tree.neighbor(of: focusedPane, toward: direction, in: bounds.size) {
      focus(neighbor)
    }
  }

  private func setFocusedPane(_ pane: NodeID) {
    focusedPane = pane
    refreshFocusMarks()
  }

  /// The focused pane is marked, but only when it has a neighbor to be told apart from.
  private func refreshFocusMarks() {
    for (id, view) in paneViews {
      view.isFocused = id == focusedPane
      view.showsFocusMarker = paneViews.count > 1
    }
  }

  /// A click inside a pane's applet moves the first responder without asking this view. The
  /// window reports every event it handles, so the focus mark follows the responder from there.
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()

    if let updateObserver {
      NotificationCenter.default.removeObserver(updateObserver)
      self.updateObserver = nil
    }

    guard let window else { return }

    updateObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didUpdateNotification, object: window, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.followResponder() }
    }
  }

  private func followResponder() {
    guard let responder = window?.firstResponder as? NSView else { return }

    for (id, view) in paneViews where responder.isDescendant(of: view) {
      if id != focusedPane { setFocusedPane(id) }
      return
    }
  }

  // MARK: Layout

  override func layout() {
    super.layout()

    let layout = tree.layout(in: bounds.size)

    for (id, view) in paneViews {
      if let frame = layout.frames[id] { view.frame = snapped(frame) }
    }

    var live = Set<DividerKey>()

    for divider in layout.dividers {
      let key = DividerKey(leading: divider.leading, trailing: divider.trailing)
      live.insert(key)

      let view = dividerViews[key] ?? makeDivider(key, axis: divider.axis)
      view.axis = divider.axis
      view.frame = snapped(divider.frame)
    }

    for key in dividerViews.keys where !live.contains(key) {
      dividerViews.removeValue(forKey: key)?.removeFromSuperview()
    }
  }

  private func makeDivider(_ key: DividerKey, axis: Axis) -> DividerView {
    let view = DividerView(leading: key.leading, trailing: key.trailing, axis: axis)
    view.apply(palette)
    view.onDrag = { [weak self] divider, point in self?.drag(divider, to: point) }
    dividerViews[key] = view
    addSubview(view)
    return view
  }

  /// Rounds a frame's edges, so neighbors share a whole-point edge and leave no seam.
  private func snapped(_ rect: CGRect) -> NSRect {
    let minX = rect.minX.rounded()
    let minY = rect.minY.rounded()
    return NSRect(
      x: minX, y: minY, width: rect.maxX.rounded() - minX, height: rect.maxY.rounded() - minY)
  }

  private func drag(_ divider: DividerView, to point: NSPoint) {
    let delta = divider.axis == .row ? point.x - divider.frame.midX : point.y - divider.frame.midY

    guard delta != 0 else { return }

    _ = try? tree.moveDivider(
      between: divider.leading, and: divider.trailing, by: delta, in: bounds.size)
    needsLayout = true
    layoutSubtreeIfNeeded()
  }

  /// Moves a divider as a drag would, by points along its axis. Returns the distance it moved.
  @discardableResult
  func moveDivider(between leading: NodeID, and trailing: NodeID, by delta: CGFloat) throws
    -> CGFloat
  {
    let moved = try tree.moveDivider(
      between: leading, and: trailing, by: delta, in: bounds.size)
    needsLayout = true
    layoutSubtreeIfNeeded()
    return moved
  }

  // MARK: Theme

  func apply(_ palette: ThemePalette) {
    self.palette = palette

    for view in paneViews.values { view.apply(palette) }
    for view in dividerViews.values { view.apply(palette) }
  }
}

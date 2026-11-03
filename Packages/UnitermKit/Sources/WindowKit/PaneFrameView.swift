import AppKit
import AppletKit
import PaneModel
import Theme

/// Hosts one applet's view inside a pane. A gutter around the applet holds the focus marker.
@MainActor
final class PaneFrameView: NSView {
  static let gutter: CGFloat = 2

  let paneID: NodeID
  private(set) var applet: any Applet

  private var palette: ThemePalette = .latte

  var isFocused = false {
    didSet { refresh() }
  }

  /// A lone pane has no neighbor to tell apart from, so it shows no marker.
  var showsFocusMarker = false {
    didSet { refresh() }
  }

  override var wantsUpdateLayer: Bool { true }

  override var isFlipped: Bool { true }

  override var mouseDownCanMoveWindow: Bool { false }

  init(paneID: NodeID, applet: any Applet) {
    self.paneID = paneID
    self.applet = applet
    super.init(frame: .zero)

    wantsLayer = true
    applet.view.frame = innerFrame
    addSubview(applet.view)

    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityIdentifier("pane-\(paneID)")
    refresh()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  /// Puts another applet in this pane. The old applet's view leaves, and the caller closes it.
  func replaceApplet(_ replacement: any Applet) {
    applet.view.removeFromSuperview()
    applet = replacement

    replacement.view.frame = innerFrame
    addSubview(replacement.view)
    replacement.apply(palette)
  }

  private var innerFrame: NSRect {
    Self.appletFrame(in: bounds)
  }

  /// The applet's frame for a pane with these bounds: the bounds less the gutter on every side.
  /// It is the bounds inset by hand on purpose. Core Graphics returns the null rect, with an
  /// infinite origin, for bounds smaller than the inset, and a pane is zero size before its
  /// first layout.
  static func appletFrame(in bounds: NSRect) -> NSRect {
    NSRect(
      x: bounds.minX + gutter, y: bounds.minY + gutter,
      width: max(0, bounds.width - 2 * gutter), height: max(0, bounds.height - 2 * gutter))
  }

  override func resizeSubviews(withOldSize oldSize: NSSize) {
    applet.view.frame = innerFrame
  }

  func apply(_ palette: ThemePalette) {
    self.palette = palette
    applet.apply(palette)
    refresh()
  }

  private func refresh() {
    setAccessibilityValue(isFocused ? "focused" : "unfocused")
    needsDisplay = true
  }

  override func updateLayer() {
    guard let layer else { return }

    layer.backgroundColor = palette[.base].cgColor
    layer.borderWidth = isFocused && showsFocusMarker ? Self.gutter : 0
    layer.borderColor = palette[.blue].cgColor
  }
}

import AppKit
import PaneModel
import Theme

/// The handle between two adjacent children of a split. Dragging it moves space between them.
@MainActor
final class DividerView: NSView {
  let leading: NodeID
  let trailing: NodeID

  var axis: Axis {
    didSet {
      if axis != oldValue { window?.invalidateCursorRects(for: self) }
    }
  }

  /// Called with the pointer's position along the axis, in the pane area's coordinates.
  var onDrag: ((DividerView, NSPoint) -> Void)?

  private var palette: ThemePalette = .latte
  private var grabOffset: CGFloat = 0

  override var wantsUpdateLayer: Bool { true }

  override var isFlipped: Bool { true }

  override var mouseDownCanMoveWindow: Bool { false }

  override var acceptsFirstResponder: Bool { false }

  init(leading: NodeID, trailing: NodeID, axis: Axis) {
    self.leading = leading
    self.trailing = trailing
    self.axis = axis
    super.init(frame: .zero)

    wantsLayer = true
    setAccessibilityElement(true)
    setAccessibilityRole(.splitter)
    setAccessibilityIdentifier("divider-\(leading)-\(trailing)")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  func apply(_ palette: ThemePalette) {
    self.palette = palette
    needsDisplay = true
  }

  override func updateLayer() {
    layer?.backgroundColor = palette[.surface1].cgColor
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: axis == .row ? .resizeLeftRight : .resizeUpDown)
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) {
    guard let area = superview else { return }

    let point = area.convert(event.locationInWindow, from: nil)
    grabOffset = (axis == .row ? point.x - frame.midX : point.y - frame.midY)
  }

  override func mouseDragged(with event: NSEvent) {
    guard let area = superview else { return }

    var point = area.convert(event.locationInWindow, from: nil)
    if axis == .row {
      point.x -= grabOffset
    } else {
      point.y -= grabOffset
    }

    onDrag?(self, point)
  }
}

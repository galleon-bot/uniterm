import AppKit
import Theme

extension ThemePalette {
  func color(for tone: BarTone) -> NSColor {
    switch tone {
    case .normal: return self[.subtext1].nsColor
    case .emphasized: return self[.text].nsColor
    case .warning: return self[.yellow].nsColor
    case .error: return self[.red].nsColor
    }
  }
}

/// The status bar region. It lays out the window's segments in one row.
///
/// The bar knows nothing about where it docks. The window moves this one view between edges, so a
/// dock change cannot change what the bar shows. A click anywhere on the bar asks to toggle the
/// history.
@MainActor
final class StatusBarView: NSView {
  static let height: CGFloat = 22

  /// Runs when the user clicks the bar.
  var onActivate: (() -> Void)?

  /// Runs when the user clicks the dismiss control.
  var onDismiss: (() -> Void)?

  /// Runs when the user clicks the control that hangs up the hidden closed panes.
  var onHangUp: (() -> Void)?

  private(set) var segments: [BarSegment] = []

  private let stack = NSStackView()
  private var segmentViews: [BarSegmentID: SegmentView] = [:]
  private var palette: ThemePalette = .latte

  override var wantsUpdateLayer: Bool { true }

  /// A click on the bar toggles the history. It must not drag the window.
  override var mouseDownCanMoveWindow: Bool { false }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.distribution = .fill
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])

    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityIdentifier("status-bar")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  /// Every click on the bar lands on the bar, so a label cannot swallow it.
  override func hitTest(_ point: NSPoint) -> NSView? {
    guard let superview else { return nil }

    return bounds.contains(convert(point, from: superview)) ? self : nil
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)

    if let dismiss = frame(of: .dismiss), dismiss.insetBy(dx: -4, dy: -4).contains(point) {
      onDismiss?()
    } else if let hangUp = frame(of: .graceHangUp), hangUp.insetBy(dx: -4, dy: -4).contains(point) {
      onHangUp?()
    } else {
      onActivate?()
    }
  }

  /// Where a segment sits in the bar, or nil when it is not showing.
  func frame(of id: BarSegmentID) -> NSRect? {
    guard let view = segmentViews[id], view.superview != nil else { return nil }

    return convert(view.bounds, from: view)
  }

  func apply(_ palette: ThemePalette) {
    self.palette = palette
    needsDisplay = true

    for view in segmentViews.values {
      view.apply(palette)
    }
  }

  func show(_ segments: [BarSegment]) {
    self.segments = segments

    let live = Set(segments.map(\.id))
    for id in segmentViews.keys where !live.contains(id) {
      segmentViews.removeValue(forKey: id)?.removeFromSuperview()
    }

    var ordered: [SegmentView] = []

    for segment in segments {
      let view = segmentViews[segment.id] ?? makeSegmentView(segment.id)
      view.show(segment)
      ordered.append(view)
    }

    stack.setViews(ordered, in: .leading)
  }

  override func updateLayer() {
    layer?.backgroundColor = palette[.mantle].cgColor
  }

  private func makeSegmentView(_ id: BarSegmentID) -> SegmentView {
    let view = SegmentView(id: id)
    view.apply(palette)
    segmentViews[id] = view
    return view
  }
}

/// One segment: an optional icon and an optional line of text.
@MainActor
private final class SegmentView: NSStackView {
  private let id: BarSegmentID
  private let icon = NSImageView()
  private let label = NSTextField(labelWithString: "")
  private var palette: ThemePalette = .latte
  private var segment: BarSegment?

  init(id: BarSegmentID) {
    self.id = id
    super.init(frame: .zero)

    orientation = .horizontal
    alignment = .centerY
    spacing = 4

    icon.imageScaling = .scaleProportionallyDown
    icon.setContentHuggingPriority(.required, for: .horizontal)
    icon.setContentCompressionResistancePriority(.required, for: .horizontal)

    label.lineBreakMode = .byTruncatingTail
    label.maximumNumberOfLines = 1

    addArrangedSubview(icon)
    addArrangedSubview(label)

    // The message area takes the room that the other segments leave. They keep their own width.
    let flexible = id == .message
    setContentHuggingPriority(flexible ? .defaultLow : .defaultHigh, for: .horizontal)
    setContentCompressionResistancePriority(
      flexible ? NSLayoutConstraint.Priority(10) : .defaultHigh, for: .horizontal)
    label.setContentCompressionResistancePriority(
      flexible ? NSLayoutConstraint.Priority(10) : .defaultHigh, for: .horizontal)
    label.setContentHuggingPriority(flexible ? .defaultLow : .defaultHigh, for: .horizontal)
  }

  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  func apply(_ palette: ThemePalette) {
    self.palette = palette

    if let segment {
      show(segment)
    }
  }

  func show(_ segment: BarSegment) {
    self.segment = segment

    let color = palette.color(for: segment.tone)
    let weight: NSFont.Weight = segment.tone == .emphasized ? .semibold : .regular

    label.font = .systemFont(ofSize: 11, weight: weight)
    label.textColor = color
    label.stringValue = segment.text ?? ""
    label.isHidden = segment.text == nil

    if let name = segment.symbolName,
      let image = NSImage(
        systemSymbolName: name, accessibilityDescription: segment.accessibilityLabel)
    {
      icon.image = image.withSymbolConfiguration(.init(pointSize: 11, weight: weight))
      icon.contentTintColor = color
      icon.isHidden = false
    } else {
      icon.image = nil
      icon.isHidden = true
    }

    // The text carries the identifier when there is any. An icon-only segment carries it itself.
    if segment.text != nil {
      label.setAccessibilityIdentifier(id.identifier)
      icon.setAccessibilityElement(false)
    } else {
      icon.setAccessibilityIdentifier(id.identifier)
      icon.setAccessibilityElement(true)
      icon.setAccessibilityLabel(segment.accessibilityLabel)
    }
  }
}

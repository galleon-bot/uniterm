import AppKit
import StatusKit
import Theme

/// The expanded status bar: the history of messages, newest first, with each one's level and
/// source. It floats over the pane area against the bar, so opening it never resizes a pane.
@MainActor
final class HistoryPanelView: NSView {
  static let height: CGFloat = 240

  private let scroll = NSScrollView()
  private let rows = FlippedStackView()
  private var palette: ThemePalette = .latte
  private var messages: [StatusMessage] = []

  /// The lines on show, newest first. Tests read it.
  private(set) var lines: [String] = []

  override var wantsUpdateLayer: Bool { true }

  override var mouseDownCanMoveWindow: Bool { false }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    rows.orientation = .vertical
    rows.alignment = .leading
    rows.spacing = 2
    rows.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
    rows.translatesAutoresizingMaskIntoConstraints = false

    scroll.documentView = rows
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    scroll.translatesAutoresizingMaskIntoConstraints = false
    addSubview(scroll)

    NSLayoutConstraint.activate([
      scroll.topAnchor.constraint(equalTo: topAnchor),
      scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
      scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
      rows.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
      rows.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
      rows.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
    ])

    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityIdentifier("status-history")
    isHidden = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func updateLayer() {
    layer?.backgroundColor = palette[.mantle].cgColor
    layer?.borderColor = palette[.surface1].cgColor
    layer?.borderWidth = 1
  }

  func apply(_ palette: ThemePalette) {
    self.palette = palette
    needsDisplay = true
    show(messages)
  }

  /// Shows the history, newest first.
  func show(_ history: [StatusMessage]) {
    messages = history

    for view in rows.arrangedSubviews {
      rows.removeArrangedSubview(view)
      view.removeFromSuperview()
    }

    lines = history.reversed().map(StatusBarContent.historyLine)

    if history.isEmpty {
      rows.addArrangedSubview(row("No messages yet.", tone: .normal, identifier: "history-empty"))
      return
    }

    for message in history.reversed() {
      rows.addArrangedSubview(
        row(
          StatusBarContent.historyLine(message),
          tone: StatusBarContent.tone(for: message.level), identifier: "history-row"))
    }
  }

  private func row(_ text: String, tone: BarTone, identifier: String) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: 11)
    label.textColor = palette.color(for: tone)
    label.lineBreakMode = .byTruncatingTail
    label.maximumNumberOfLines = 1
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    label.setAccessibilityIdentifier(identifier)
    return label
  }
}

/// A stack whose first row sits at the top of a scroll view.
private final class FlippedStackView: NSStackView {
  override var isFlipped: Bool { true }
}

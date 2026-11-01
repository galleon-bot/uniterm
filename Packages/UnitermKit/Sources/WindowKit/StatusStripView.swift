import AppKit
import StatusKit
import Theme

/// A minimal strip that shows the window's current status message.
///
/// It stands in until the status bar region replaces it. The strip shows the source and text of
/// the message on the bar and nothing else.
@MainActor
final class StatusStripView: NSView {
  static let height: CGFloat = 22

  private let label = NSTextField(labelWithString: "")
  private var palette: ThemePalette = .latte
  private var display: StatusDisplay?

  override var wantsUpdateLayer: Bool { true }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    label.font = .systemFont(ofSize: 11)
    label.lineBreakMode = .byTruncatingTail
    label.translatesAutoresizingMaskIntoConstraints = false
    label.setAccessibilityIdentifier("status-message")
    addSubview(label)

    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])

    setAccessibilityIdentifier("status-strip")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  func apply(_ palette: ThemePalette) {
    self.palette = palette
    needsDisplay = true
    refresh()
  }

  func show(_ display: StatusDisplay?) {
    self.display = display
    refresh()
  }

  override func updateLayer() {
    layer?.backgroundColor = palette[.mantle].cgColor
  }

  private func refresh() {
    guard let display else {
      label.stringValue = ""
      return
    }

    var text = "\(display.message.source.label): \(display.message.text)"
    if display.collapsedErrors > 0 {
      text += "  (+\(display.collapsedErrors) more errors)"
    }

    label.stringValue = text

    switch display.message.level {
    case .info: label.textColor = palette[.subtext1].nsColor
    case .warning: label.textColor = palette[.yellow].nsColor
    case .error: label.textColor = palette[.red].nsColor
    }
  }
}

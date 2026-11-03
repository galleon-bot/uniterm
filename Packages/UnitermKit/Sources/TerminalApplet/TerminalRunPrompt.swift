import AppKit
import Theme

/// What a restored program-mode terminal shows in place of a session. It names the command and
/// waits for the user to run it. Nothing starts until the Run button is pressed.
@MainActor
final class TerminalRunPrompt: NSView {
  private let heading = NSTextField(labelWithString: "This pane ran a program")
  private let commandLabel = NSTextField(labelWithString: "")
  private let button = NSButton()
  private let stack = NSStackView()
  private var palette: ThemePalette = .latte

  var onRun: (() -> Void)?

  var command = "" {
    didSet { commandLabel.stringValue = command }
  }

  /// The Run button, so the applet can give it the keyboard.
  var runButton: NSView { button }

  override var isFlipped: Bool { true }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    wantsLayer = true

    heading.font = .systemFont(ofSize: 12)
    heading.alignment = .center

    commandLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    commandLabel.alignment = .center
    commandLabel.lineBreakMode = .byTruncatingMiddle
    commandLabel.maximumNumberOfLines = 3
    commandLabel.setAccessibilityIdentifier("terminal-run-command")

    button.title = "Run"
    button.bezelStyle = .rounded
    button.target = self
    button.action = #selector(runPressed(_:))
    button.setAccessibilityIdentifier("terminal-run-button")

    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 10
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.addArrangedSubview(heading)
    stack.addArrangedSubview(commandLabel)
    stack.addArrangedSubview(button)
    addSubview(stack)

    // The margins yield when the prompt is narrower than them. It is zero wide until its pane's
    // first layout, and a required margin would conflict with that and log on every launch.
    let leading = stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16)
    let trailing = stack.trailingAnchor.constraint(
      lessThanOrEqualTo: trailingAnchor, constant: -16)
    leading.priority = .init(999)
    trailing.priority = .init(999)

    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
      leading,
      trailing,
    ])

    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityIdentifier("terminal-run-prompt")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  func apply(_ palette: ThemePalette) {
    self.palette = palette
    layer?.backgroundColor = palette[.base].cgColor
    heading.textColor = palette[.subtext1].nsColor
    commandLabel.textColor = palette[.text].nsColor
  }

  /// Presses the button as the user would.
  func run() {
    onRun?()
  }

  @objc private func runPressed(_ sender: Any?) {
    run()
  }
}

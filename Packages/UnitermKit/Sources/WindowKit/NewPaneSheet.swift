import AppKit

/// Asks which applet a new pane should run. It offers the terminal in shell mode, and in program
/// mode with a command.
@MainActor
final class NewPaneSheet: NSObject, NSTextFieldDelegate {
  private var form = NewPaneForm()
  private let alert = NSAlert()
  private let popup = NSPopUpButton(frame: .zero, pullsDown: false)
  private let field = NSTextField(frame: .zero)
  private var openButton: NSButton?

  /// Shows the sheet on `window`. `completion` runs with the choice, or never when the user
  /// cancels.
  static func present(
    on window: NSWindow, completion: @escaping @MainActor (AppletChoice) -> Void
  ) {
    NewPaneSheet().show(on: window, completion: completion)
  }

  private func show(on window: NSWindow, completion: @escaping @MainActor (AppletChoice) -> Void) {
    alert.messageText = "Open a new pane"
    alert.informativeText = "Choose what the pane runs."
    openButton = alert.addButton(withTitle: "Open")
    alert.addButton(withTitle: "Cancel")
    alert.window.setAccessibilityIdentifier("new-pane-sheet")

    for mode in NewPaneForm.Mode.allCases {
      popup.addItem(withTitle: mode.title)
    }
    popup.target = self
    popup.action = #selector(modeChanged(_:))
    popup.setAccessibilityIdentifier("pane-applet")

    field.placeholderString = "Command, such as htop or tail -f log"
    field.delegate = self
    field.isHidden = true
    field.setAccessibilityIdentifier("pane-command")

    let stack = NSStackView(views: [popup, field])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    stack.frame = NSRect(x: 0, y: 0, width: 320, height: 56)
    popup.widthAnchor.constraint(equalToConstant: 320).isActive = true
    field.widthAnchor.constraint(equalToConstant: 320).isActive = true
    stack.detachesHiddenViews = true

    alert.accessoryView = stack
    alert.layout()
    alert.window.initialFirstResponder = popup
    updateOpenButton()

    alert.beginSheetModal(for: window) { [self] response in
      guard response == .alertFirstButtonReturn, let choice = form.choice else { return }

      completion(choice)
    }
  }

  @objc private func modeChanged(_ sender: NSPopUpButton) {
    form.mode = NewPaneForm.Mode(rawValue: sender.indexOfSelectedItem) ?? .shell
    field.isHidden = form.mode != .program
    alert.layout()
    updateOpenButton()

    if form.mode == .program {
      alert.window.makeFirstResponder(field)
    }
  }

  func controlTextDidChange(_ obj: Notification) {
    form.command = field.stringValue
    updateOpenButton()
  }

  private func updateOpenButton() {
    openButton?.isEnabled = form.choice != nil
  }
}

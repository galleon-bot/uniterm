import AppKit

/// A question the window asks before it ends something that undo cannot bring back.
public struct CloseConfirmation: Sendable, Equatable {
  public var title: String
  public var detail: String

  /// What is running and would end, by tab title or by command in program mode.
  public var labels: [String]

  public var confirmTitle: String
  public var cancelTitle: String

  public init(
    title: String, detail: String, labels: [String] = [], confirmTitle: String, cancelTitle: String
  ) {
    self.title = title
    self.detail = detail
    self.labels = labels
    self.confirmTitle = confirmTitle
    self.cancelTitle = cancelTitle
  }
}

/// Shows a confirmation and returns the user's answer. Tests replace it.
public typealias CloseConfirmer =
  @MainActor (_ request: CloseConfirmation, _ window: NSWindow?) async -> Bool

public enum CloseDialog {
  /// The most labels the dialog lists before it counts the rest.
  static let visibleLabels = 8

  /// The lines a dialog lists for the labels. A label is untrusted text from a program's title, so
  /// control characters are already gone and the length is capped.
  static func listing(of labels: [String]) -> String {
    let shown = labels.prefix(visibleLabels).map { "\u{2022} \($0)" }
    var lines = Array(shown)

    if labels.count > visibleLabels {
      lines.append("and \(labels.count - visibleLabels) more")
    }

    return lines.joined(separator: "\n")
  }

  /// Asks in a sheet on the window, or in a modal alert when the window is not on screen. Cancel is
  /// the default button, so a stray Return keeps what is running.
  @MainActor
  public static let present: CloseConfirmer = { request, window in
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = request.title
    alert.informativeText = [request.detail, listing(of: request.labels)]
      .filter { !$0.isEmpty }
      .joined(separator: "\n\n")
    alert.addButton(withTitle: request.cancelTitle)
    alert.addButton(withTitle: request.confirmTitle)
    alert.buttons[0].keyEquivalent = "\r"
    alert.buttons[1].keyEquivalent = ""
    alert.window.setAccessibilityIdentifier("close-confirmation")

    let response: NSApplication.ModalResponse
    if let window, window.isVisible {
      response = await alert.beginSheetModal(for: window)
    } else {
      response = alert.runModal()
    }

    return response == .alertSecondButtonReturn
  }
}

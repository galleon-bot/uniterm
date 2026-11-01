import AppKit
import Theme

/// The window's content. Later work replaces the placeholder with the pane tree.
///
/// The content lies inside the safe area, so it never covers the traffic lights.
@MainActor
final class MainContentViewController: NSViewController {
  private let chrome = ChromeView()
  private let placeholder = NSTextField(labelWithString: "uniterm")

  override func loadView() {
    chrome.setAccessibilityElement(true)
    chrome.setAccessibilityRole(.group)
    chrome.setAccessibilityIdentifier("content-area")
    placeholder.font = .systemFont(ofSize: 28, weight: .semibold)
    placeholder.setAccessibilityIdentifier("content-label")
    placeholder.translatesAutoresizingMaskIntoConstraints = false
    chrome.addSubview(placeholder)

    NSLayoutConstraint.activate([
      placeholder.centerXAnchor.constraint(equalTo: chrome.safeAreaLayoutGuide.centerXAnchor),
      placeholder.centerYAnchor.constraint(equalTo: chrome.safeAreaLayoutGuide.centerYAnchor),
    ])

    view = chrome
  }

  func apply(_ palette: ThemePalette) {
    chrome.apply(palette)
    placeholder.textColor = palette[.text].nsColor
  }
}

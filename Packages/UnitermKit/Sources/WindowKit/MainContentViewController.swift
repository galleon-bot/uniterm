import AppKit
import StatusKit
import Theme

/// The window's content: one pane, with a placeholder strip for the current status message.
///
/// The content lies inside the safe area, so it never covers the traffic lights. Later work
/// replaces the single pane with the pane tree, and the strip with the status bar region.
@MainActor
final class MainContentViewController: NSViewController {
  private let chrome = ChromeView()
  private let strip = StatusStripView()
  private let paneView: NSView

  init(paneView: NSView) {
    self.paneView = paneView
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func loadView() {
    chrome.setAccessibilityElement(true)
    chrome.setAccessibilityRole(.group)
    chrome.setAccessibilityIdentifier("content-area")

    paneView.translatesAutoresizingMaskIntoConstraints = false
    strip.translatesAutoresizingMaskIntoConstraints = false
    chrome.addSubview(paneView)
    chrome.addSubview(strip)

    let guide = chrome.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      paneView.topAnchor.constraint(equalTo: guide.topAnchor),
      paneView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
      paneView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
      paneView.bottomAnchor.constraint(equalTo: strip.topAnchor),
      strip.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
      strip.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
      strip.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
      strip.heightAnchor.constraint(equalToConstant: StatusStripView.height),
    ])

    view = chrome
  }

  func apply(_ palette: ThemePalette) {
    chrome.apply(palette)
    strip.apply(palette)
  }

  func showStatus(_ display: StatusDisplay?) {
    strip.show(display)
  }
}

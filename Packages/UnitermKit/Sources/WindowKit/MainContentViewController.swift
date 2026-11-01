import AppKit
import StatusKit
import Theme

/// The window's content: the pane area, with a placeholder strip for the current status message.
///
/// The content lies inside the safe area, so it never covers the traffic lights. Later work
/// replaces the strip with the status bar region.
@MainActor
final class MainContentViewController: NSViewController {
  private let chrome = ChromeView()
  private let strip = StatusStripView()
  private let paneView: NSView

  /// Runs after every layout pass, since the safe area that sets the window's minimum size can
  /// change with it.
  var onLayout: (() -> Void)?

  /// The height of everything in the window that is not the pane area.
  var chromeHeight: CGFloat {
    chrome.safeAreaInsets.top + StatusStripView.height
  }

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

  override func viewDidLayout() {
    super.viewDidLayout()
    onLayout?()
  }

  func apply(_ palette: ThemePalette) {
    chrome.apply(palette)
    strip.apply(palette)
  }

  func showStatus(_ display: StatusDisplay?) {
    strip.show(display)
  }
}

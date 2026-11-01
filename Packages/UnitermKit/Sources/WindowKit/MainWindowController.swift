import AppKit
import Theme

/// Hosts one window with a full-size content view. Content extends under the title bar, and the
/// standard traffic lights stay.
@MainActor
public final class MainWindowController: NSWindowController {
  private let contentController = MainContentViewController()
  private let appearance: AppearanceController
  private var appearanceToken: UUID?

  public init(appearance: AppearanceController) {
    self.appearance = appearance

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false)
    window.title = "uniterm"
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.minSize = NSSize(width: 480, height: 320)
    window.isReleasedWhenClosed = false
    window.setAccessibilityIdentifier("main-window")
    window.contentViewController = contentController
    window.setContentSize(NSSize(width: 960, height: 640))
    window.center()

    super.init(window: window)

    appearanceToken = appearance.addObserver { [weak self] palette in
      self?.apply(palette)
    }
  }

  isolated deinit {
    if let appearanceToken {
      appearance.removeObserver(appearanceToken)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  private func apply(_ palette: ThemePalette) {
    window?.backgroundColor = palette[.base].nsColor
    contentController.apply(palette)
  }
}

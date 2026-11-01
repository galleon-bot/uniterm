import AppKit
import Theme

/// The window's root view. It paints the window background from a theme token and sits under the
/// title bar, so a drag that starts on it moves the window.
@MainActor
final class ChromeView: NSView {
  override var mouseDownCanMoveWindow: Bool { true }

  override var wantsUpdateLayer: Bool { true }

  private(set) var palette: ThemePalette = .latte

  /// The accessibility value names the flavor on screen, so UI tests can see a live switch.
  func apply(_ palette: ThemePalette) {
    self.palette = palette
    setAccessibilityValue(palette.flavor.rawValue)
    needsDisplay = true
  }

  override func updateLayer() {
    layer?.backgroundColor = palette[.base].cgColor
  }
}

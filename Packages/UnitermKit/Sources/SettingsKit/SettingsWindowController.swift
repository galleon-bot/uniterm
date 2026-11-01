import AppKit
import Preferences

/// The Settings window, opened with Cmd-,. It is an AppKit window. SwiftUI forms may join it later
/// as leaf views.
@MainActor
public final class SettingsWindowController: NSWindowController {
  public init(store: SettingsStore) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 130),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false)
    window.title = "Settings"
    window.isReleasedWhenClosed = false
    window.setAccessibilityIdentifier("settings-window")
    window.contentViewController = SettingsViewController(store: store)
    window.center()

    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  /// Cmd-W is a menu item with no target that closes the pane. The responder chain ends here when
  /// Settings is the key window, so this closes Settings instead of leaving the key dead.
  @objc public func closePane(_ sender: Any?) {
    window?.performClose(sender)
  }

  public func present() {
    NSApp.activate()
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
  }
}

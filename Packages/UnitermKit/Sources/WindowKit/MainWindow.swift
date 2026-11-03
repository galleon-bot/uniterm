import AppKit

/// The window of one main window controller.
///
/// AppKit's own window answers the standard undo action by asking its undo manager, which is how a
/// text control being edited undoes its edit. That answer comes before the window controller in the
/// responder chain, so a controller method named for undo would never be reached. This window
/// answers the action itself. While a text control is being edited, it undoes the edit. Otherwise
/// the action undoes the last pane close.
///
/// The window is also uniterm's one key route. A key that matches a key equivalent in the live
/// menu goes to that menu item before any view in the window sees it. The menu is read live, so a
/// user's remap of an item in System Settings > Keyboard > App Shortcuts applies. A remap onto a
/// Control or Option chord therefore wins over a terminal that would take the key as input.
public final class MainWindow: NSWindow {
  /// Whether AppKit keeps the window on the screen it is shown on. Tests turn it off. Their frames
  /// come from screens they inject, and the display of the machine running them must not move a
  /// window that the injected screens place correctly.
  var constrainsFrameToScreen = true

  public override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
    constrainsFrameToScreen ? super.constrainFrameRect(frameRect, to: screen) : frameRect
  }

  private var isEditingText: Bool {
    firstResponder is NSText
  }

  /// The undo manager of the field being edited. A field editor can keep its own, apart from the
  /// window's, and its edits are recorded there.
  private var editingUndoManager: UndoManager? {
    (firstResponder as? NSTextView)?.undoManager ?? undoManager
  }

  /// The target of Edit > Undo Close Pane. The selector is the standard `undo:`, so the menu item
  /// keeps its place in the Edit menu and a text control gets the key when it has focus.
  @objc(undo:) public func undoCloseOrEdit(_ sender: Any?) {
    if isEditingText {
      editingUndoManager?.undo()
    } else {
      (windowController as? MainWindowController)?.undoClosePane(sender)
    }
  }

  public override func validateMenuItem(_ item: NSMenuItem) -> Bool {
    guard item.action == #selector(undoCloseOrEdit(_:)) else {
      return super.validateMenuItem(item)
    }

    if isEditingText {
      item.title = editingUndoManager?.undoMenuItemTitle ?? "Undo"
      return editingUndoManager?.canUndo ?? false
    }

    return (windowController as? MainWindowController)?.validateMenuItem(item) ?? false
  }

  // MARK: Key route

  public override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if routeToMenu(event) {
      return true
    }

    return super.performKeyEquivalent(with: event)
  }

  /// Offers the key to the launcher that holds the keyboard first, since Cmd-1 to Cmd-9 pick its
  /// entries. Then it looks for a live menu item with that key. A disabled item does not take the
  /// key, so the views and the menu see it as they always did.
  private func routeToMenu(_ event: NSEvent) -> Bool {
    guard event.type == .keyDown, let menu = NSApp.mainMenu else { return false }

    if let launcher = launcherHoldingKeyboard, launcher.performKeyEquivalent(with: event) {
      return true
    }

    guard let item = MenuKeyMatch.item(for: event, in: menu), let parent = item.menu else {
      return false
    }

    parent.update()

    guard item.isEnabled else { return false }

    parent.performActionForItem(at: parent.index(of: item))
    return true
  }

  private var launcherHoldingKeyboard: LauncherView? {
    var view = firstResponder as? NSView

    while let current = view {
      if let launcher = current as? LauncherView { return launcher }

      view = current.superview
    }

    return nil
  }

  // MARK: Mouse

  /// A press outside the floating palette hides it, and then goes to whatever it hit.
  public override func sendEvent(_ event: NSEvent) {
    switch event.type {
    case .leftMouseDown, .rightMouseDown, .otherMouseDown:
      let controller = windowController as? MainWindowController
      let hidPalette = controller?.paletteWillHandleMouseDown(event) ?? false

      super.sendEvent(event)

      if hidPalette {
        controller?.paletteDidHandleMouseDown()
      }

    default:
      super.sendEvent(event)
    }
  }
}

/// Finds the live menu item that a key event triggers.
enum MenuKeyMatch {
  private static let chordFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

  /// The item whose key equivalent matches the event. When a user's remap and a default share the
  /// key, the remapped item wins, instead of whichever sits first in the menu.
  @MainActor
  static func item(for event: NSEvent, in menu: NSMenu) -> NSMenuItem? {
    var matches: [NSMenuItem] = []
    collect(event, in: menu, into: &matches)

    return matches.first { !$0.userKeyEquivalent.isEmpty } ?? matches.first
  }

  @MainActor
  private static func collect(_ event: NSEvent, in menu: NSMenu, into matches: inout [NSMenuItem]) {
    for item in menu.items {
      if let submenu = item.submenu {
        collect(event, in: submenu, into: &matches)
      }

      if triggers(item, event) {
        matches.append(item)
      }
    }
  }

  /// A key equivalent is compared by the character it produces, so Cmd-Shift-= matches an item
  /// whose key is "+". Shift is part of that character for any key that is not a letter or a
  /// digit, so it is left out of the modifier comparison there. The Delete key sends 0x7F, and
  /// menus spell it 0x08.
  @MainActor
  static func triggers(_ item: NSMenuItem, _ event: NSEvent) -> Bool {
    guard !item.isHidden, !item.keyEquivalent.isEmpty, !item.isSeparatorItem else { return false }

    let key = canonical(item.keyEquivalent)

    guard key == canonical(event.charactersIgnoringModifiers ?? "") else { return false }

    var wanted = item.keyEquivalentModifierMask.intersection(chordFlags)
    var pressed = event.modifierFlags.intersection(chordFlags)

    if !isLetterOrDigit(key) {
      wanted.remove(.shift)
      pressed.remove(.shift)
    }

    return wanted == pressed
  }

  private static func canonical(_ key: String) -> String {
    key == "\u{7F}" ? "\u{8}" : key.lowercased()
  }

  private static func isLetterOrDigit(_ key: String) -> Bool {
    key.unicodeScalars.count == 1
      && key.unicodeScalars.allSatisfy { $0.properties.isAlphabetic || ("0"..."9").contains($0) }
  }
}

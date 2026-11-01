import AppKit

/// The window of one main window controller.
///
/// AppKit's own window answers the standard undo action by asking its undo manager, which is how a
/// text control being edited undoes its edit. That answer comes before the window controller in the
/// responder chain, so a controller method named for undo would never be reached. This window
/// answers the action itself. While a text control is being edited, it undoes the edit. Otherwise
/// the action undoes the last pane close.
public final class MainWindow: NSWindow {
  private var isEditingText: Bool {
    firstResponder is NSText
  }

  /// The target of Edit > Undo Close Pane. The selector is the standard `undo:`, so the menu item
  /// keeps its place in the Edit menu and a text control gets the key when it has focus.
  @objc(undo:) public func undoCloseOrEdit(_ sender: Any?) {
    if isEditingText {
      undoManager?.undo()
    } else {
      (windowController as? MainWindowController)?.undoClosePane(sender)
    }
  }

  public override func validateMenuItem(_ item: NSMenuItem) -> Bool {
    guard item.action == #selector(undoCloseOrEdit(_:)) else {
      return super.validateMenuItem(item)
    }

    if isEditingText {
      item.title = undoManager?.undoMenuItemTitle ?? "Undo"
      return undoManager?.canUndo ?? false
    }

    return (windowController as? MainWindowController)?.validateMenuItem(item) ?? false
  }
}

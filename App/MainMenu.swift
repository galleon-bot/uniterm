import AppKit
import TerminalSurface
import WindowKit

/// uniterm's menu. It owns every key binding. A focused terminal never keeps a key for itself:
/// Cmd-Z, Cmd-W, Cmd-T, Cmd-D, and Cmd-Q reach these items first. Items with a nil target find
/// their receiver on the responder chain, from the focused terminal up to the window controller.
@MainActor
enum MainMenu {
  static func make(target: AppDelegate) -> NSMenu {
    let main = NSMenu()

    main.addItem(appMenuItem(target: target))
    main.addItem(fileMenuItem())
    main.addItem(editMenuItem())
    main.addItem(viewMenuItem())
    main.addItem(windowMenuItem())

    return main
  }

  private static func appMenuItem(target: AppDelegate) -> NSMenuItem {
    let item = NSMenuItem()
    let menu = NSMenu()

    let settings = NSMenuItem(
      title: "Settings\u{2026}", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ","
    )
    settings.target = target
    menu.addItem(settings)
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Hide uniterm", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Quit uniterm", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

    item.submenu = menu
    return item
  }

  private static func fileMenuItem() -> NSMenuItem {
    let item = NSMenuItem()
    let menu = NSMenu(title: "File")

    menu.addItem(
      withTitle: "New Tab", action: #selector(MainWindowController.newTab(_:)), keyEquivalent: "t")
    menu.addItem(
      withTitle: "Split Pane", action: #selector(MainWindowController.splitPane(_:)),
      keyEquivalent: "d")
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Close Pane", action: #selector(MainWindowController.closePane(_:)),
      keyEquivalent: "w")

    item.submenu = menu
    return item
  }

  private static func editMenuItem() -> NSMenuItem {
    let item = NSMenuItem()
    let menu = NSMenu(title: "Edit")

    menu.addItem(
      withTitle: "Undo Close Pane", action: #selector(MainWindowController.undoClosePane(_:)),
      keyEquivalent: "z")
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Copy", action: #selector(TerminalMenuActions.copy(_:)), keyEquivalent: "c")
    menu.addItem(
      withTitle: "Paste", action: #selector(TerminalMenuActions.paste(_:)), keyEquivalent: "v")
    menu.addItem(
      withTitle: "Select All", action: #selector(TerminalMenuActions.selectAll(_:)),
      keyEquivalent: "a")

    item.submenu = menu
    return item
  }

  private static func viewMenuItem() -> NSMenuItem {
    let item = NSMenuItem()
    let menu = NSMenu(title: "View")

    menu.addItem(
      withTitle: "Bigger Text", action: #selector(TerminalMenuActions.increaseTerminalFontSize(_:)),
      keyEquivalent: "+")
    menu.addItem(
      withTitle: "Smaller Text",
      action: #selector(TerminalMenuActions.decreaseTerminalFontSize(_:)), keyEquivalent: "-")
    menu.addItem(
      withTitle: "Actual Size", action: #selector(TerminalMenuActions.resetTerminalFontSize(_:)),
      keyEquivalent: "0")
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Clear Screen", action: #selector(TerminalMenuActions.clearTerminalScreen(_:)),
      keyEquivalent: "k")

    item.submenu = menu
    return item
  }

  private static func windowMenuItem() -> NSMenuItem {
    let item = NSMenuItem()
    let menu = NSMenu(title: "Window")

    menu.addItem(
      withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")

    item.submenu = menu
    NSApp.windowsMenu = menu
    return item
  }
}

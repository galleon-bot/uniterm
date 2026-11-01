import AppKit
import TerminalSurface
import WindowKit

/// uniterm's menu. It owns every key binding. A focused terminal never keeps a key for itself:
/// Cmd-Z, Cmd-W, Cmd-T, Cmd-1 to Cmd-9, Cmd-Shift-[ and Cmd-Shift-], Cmd-D, Cmd-Shift-D, Cmd-[ and
/// Cmd-], Cmd-Option-arrows, and Cmd-Q reach these items first. Items with a nil target find their
/// receiver on the responder chain, from the focused terminal up to the window controller.
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
      withTitle: "Split Right", action: #selector(MainWindowController.splitRight(_:)),
      keyEquivalent: "d")

    let splitDown = NSMenuItem(
      title: "Split Down", action: #selector(MainWindowController.splitDown(_:)),
      keyEquivalent: "d")
    splitDown.keyEquivalentModifierMask = [.command, .shift]
    menu.addItem(splitDown)
    menu.addItem(.separator())
    // The title reads Close Tab while the focused applet has several tabs.
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
    menu.addItem(.separator())

    let history = NSMenuItem(
      title: "Show Message History",
      action: #selector(MainWindowController.toggleMessageHistory(_:)),
      keyEquivalent: "m")
    history.keyEquivalentModifierMask = [.command, .shift]
    menu.addItem(history)

    // Escape belongs to the terminal, so the dismiss key is a chord that no program sees.
    let dismiss = NSMenuItem(
      title: "Dismiss Message", action: #selector(MainWindowController.dismissMessage(_:)),
      keyEquivalent: "\u{8}")
    dismiss.keyEquivalentModifierMask = [.command, .option]
    menu.addItem(dismiss)

    item.submenu = menu
    return item
  }

  private static func windowMenuItem() -> NSMenuItem {
    let item = NSMenuItem()
    let menu = NSMenu(title: "Window")

    menu.addItem(
      withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
    menu.addItem(.separator())

    // With Shift held, a bracket key produces the brace, so the key equivalent is the brace and
    // the mask names Shift too.
    let nextTab = NSMenuItem(
      title: "Select Next Tab", action: #selector(MainWindowController.selectNextTab(_:)),
      keyEquivalent: "}")
    nextTab.keyEquivalentModifierMask = [.command, .shift]
    menu.addItem(nextTab)

    let previousTab = NSMenuItem(
      title: "Select Previous Tab", action: #selector(MainWindowController.selectPreviousTab(_:)),
      keyEquivalent: "{")
    previousTab.keyEquivalentModifierMask = [.command, .shift]
    menu.addItem(previousTab)

    for number in 1...9 {
      let item = NSMenuItem(
        title: number == 9 ? "Select Last Tab" : "Select Tab \(number)",
        action: #selector(MainWindowController.selectTabByNumber(_:)),
        keyEquivalent: String(number))
      item.tag = number
      menu.addItem(item)
    }

    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Focus Next Pane", action: #selector(MainWindowController.focusNextPane(_:)),
      keyEquivalent: "]")
    menu.addItem(
      withTitle: "Focus Previous Pane",
      action: #selector(MainWindowController.focusPreviousPane(_:)), keyEquivalent: "[")
    menu.addItem(.separator())

    let directions: [(String, Selector, Int)] = [
      (
        "Focus Pane Left", #selector(MainWindowController.focusPaneLeft(_:)), NSLeftArrowFunctionKey
      ),
      (
        "Focus Pane Right", #selector(MainWindowController.focusPaneRight(_:)),
        NSRightArrowFunctionKey
      ),
      ("Focus Pane Up", #selector(MainWindowController.focusPaneUp(_:)), NSUpArrowFunctionKey),
      (
        "Focus Pane Down", #selector(MainWindowController.focusPaneDown(_:)), NSDownArrowFunctionKey
      ),
    ]

    for (title, action, key) in directions {
      let direction = NSMenuItem(
        title: title, action: action,
        keyEquivalent: String(UnicodeScalar(UInt32(key)).map(Character.init) ?? " "))
      direction.keyEquivalentModifierMask = [.command, .option]
      menu.addItem(direction)
    }

    item.submenu = menu
    NSApp.windowsMenu = menu
    return item
  }
}

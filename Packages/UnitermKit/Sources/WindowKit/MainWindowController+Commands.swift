import AppKit
import AppletKit
import PaneModel
import StatusKit

/// Where the focus moves, from a given pane.
enum PaneFocusMove {
  case next
  case previous
  case toward(Direction)
}

// MARK: Dispatch

extension MainWindowController {
  /// The context for a command that nothing in particular aimed. While the palette shows, the
  /// target is the pane that had focus before it. Otherwise it is the focused pane. This is the
  /// one place where the focused pane is read to build a context.
  func commandContext() -> CommandContext {
    CommandContext(controller: self, pane: paletteTarget ?? paneArea.focusedPane)
  }

  /// Runs a command the way a key binding or a menu item asks for it. While the palette shows, the
  /// palette's rules apply: its toggle and Cmd-W only dismiss it, and any other command dismisses
  /// it first and then runs on the pane that had focus before it.
  public func dispatch(_ id: CommandID) {
    switch PaletteDispatch.rule(for: id, paletteShown: isPaletteVisible) {
    case .run:
      commands.run(id, in: commandContext())

    case .dismissOnly:
      hideCommandPalette(restoringFocus: true)

    case .dismissThenRun:
      let context = commandContext()
      hideCommandPalette(restoringFocus: true)
      commands.run(id, in: context)
    }
  }

  func commandID(for item: NSMenuItem) -> CommandID? {
    switch item.action {
    case #selector(newTab(_:)): return .newTab
    case #selector(splitRight(_:)): return .splitRight
    case #selector(splitDown(_:)): return .splitDown
    case #selector(closePane(_:)): return .close
    case #selector(selectNextTab(_:)): return .selectNextTab
    case #selector(selectPreviousTab(_:)): return .selectPreviousTab
    case #selector(selectTabByNumber(_:)): return .selectTab(number: min(max(item.tag, 1), 9))
    case #selector(focusNextPane(_:)): return .focusNextPane
    case #selector(focusPreviousPane(_:)): return .focusPreviousPane
    case #selector(focusPaneLeft(_:)): return .focusPaneLeft
    case #selector(focusPaneRight(_:)): return .focusPaneRight
    case #selector(focusPaneUp(_:)): return .focusPaneUp
    case #selector(focusPaneDown(_:)): return .focusPaneDown
    case #selector(biggerText(_:)): return .biggerText
    case #selector(smallerText(_:)): return .smallerText
    case #selector(actualSize(_:)): return .actualSize
    case #selector(clearScreen(_:)): return .clearScreen
    case #selector(minimizeWindow(_:)): return .minimizeWindow
    case #selector(toggleMessageHistory(_:)): return .toggleMessageHistory
    case #selector(dismissMessage(_:)): return .dismissMessage
    case #selector(toggleCommandPalette(_:)): return .showCommandPalette
    default: return nil
    }
  }

  func postPaneGone(for title: String) {
    statusCenter.post(
      level: .warning, source: .uniterm,
      text:
        "\u{201C}\(title)\u{201D} did not run, because the pane it was aimed at has closed. "
        + "Focus a pane and try again."
    )
  }
}

// MARK: Actions

extension MainWindowController {
  func tabbedApplet(in pane: NodeID) -> (any TabbedApplet)? {
    paneArea.applet(for: pane) as? any TabbedApplet
  }

  func textApplet(in pane: NodeID) -> (any TextActionApplet)? {
    paneArea.applet(for: pane) as? any TextActionApplet
  }

  func commandTabbedApplet(_ context: CommandContext) -> (any TabbedApplet)? {
    context.pane.flatMap { tabbedApplet(in: $0) }
  }

  /// Opens a tab in the pane's applet. A program-mode terminal has one tab, so it opens none.
  func openTab(in pane: NodeID?) {
    guard paneActionsEnabled, let pane, let applet = tabbedApplet(in: pane), applet.canOpenTab
    else { return }

    applet.openTab()
  }

  /// Selects the tab numbered `number`, counting from 1. Number 9 selects the last tab.
  func selectTab(number: Int, in pane: NodeID?) {
    guard paneActionsEnabled, let pane, let applet = tabbedApplet(in: pane), number > 0 else {
      return
    }

    applet.selectTab(at: number == 9 ? applet.tabCount - 1 : number - 1)
  }

  func stepTab(by step: Int, in pane: NodeID?) {
    guard paneActionsEnabled, let pane, let applet = tabbedApplet(in: pane), applet.tabCount > 1
    else { return }

    let count = applet.tabCount
    applet.selectTab(at: (applet.selectedTabIndex + step + count) % count)
  }

  func moveFocus(_ move: PaneFocusMove, from pane: NodeID?) {
    guard paneActionsEnabled, let pane else { return }

    let target: NodeID?

    switch move {
    case .next: target = paneArea.pane(after: pane)
    case .previous: target = paneArea.pane(before: pane)
    case .toward(let direction): target = paneArea.neighbor(of: pane, toward: direction)
    }

    if let target {
      paneArea.focus(target)
    }
  }

  func perform(_ action: TextAction, in pane: NodeID?) {
    guard let pane, let applet = textApplet(in: pane), applet.canPerform(action) else { return }

    applet.perform(action)
  }

  /// Closes the pane's selected tab when its applet has several. Otherwise it closes the pane,
  /// and with one pane left the window closes too.
  ///
  /// A tab running something asks first, and the applet does the asking. A pane close asks when any
  /// of its tabs is running something. A close that ends the window asks when anything in the
  /// window is running.
  func closeTabOrPane(_ pane: NodeID?) {
    guard paneActionsEnabled, let pane else { return }

    if let applet = tabbedApplet(in: pane), applet.tabCount > 1 {
      Task { @MainActor in _ = await applet.closeSelectedTab() }
      return
    }

    closePane(pane, appletEnded: false)
  }

  func toggleHistory() {
    setHistoryVisible(!historyVisible)
  }
}

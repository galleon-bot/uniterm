import AppKit
import AppletKit
import PaneModel

/// The commands that uniterm itself owns. Every UTERM-001 key binding is one, including the
/// terminal ones, until applets own their own commands.
///
/// The standard edit actions are not here. Cut, copy, paste, select all, undo, and redo stay
/// responder-chain menu items, since a command would act on the pane and not on a text field
/// inside it.
@MainActor
enum StandardCommands {
  static func make(app: AppCommandHooks) -> [Command] {
    var commands = appCommands(app) + paneCommands() + textCommands() + windowCommands()

    for number in 1...9 {
      commands.append(
        Command(
          .selectTab(number: number), number == 9 ? "Select Last Tab" : "Select Tab \(number)",
          scope: .pane, listedInPalette: false,
          isAvailable: { $0.hasSeveralTabs },
          run: { context in
            context.controller?.selectTab(number: number, in: context.pane)
          }))
    }

    return commands
  }

  private static func appCommands(_ app: AppCommandHooks) -> [Command] {
    [
      Command(.newWindow, "New Window", scope: .app) { _ in app.newWindow() },
      Command(.showSettings, "Settings", scope: .app) { _ in app.showSettings() },
      Command(.hideApp, "Hide uniterm", scope: .app) { _ in NSApp.hide(nil) },
      Command(.quit, "Quit uniterm", scope: .app) { _ in NSApp.terminate(nil) },
    ]
  }

  private static func paneCommands() -> [Command] {
    [
      Command(
        .newTab, "New Tab", scope: .pane,
        isAvailable: { $0.canRun { $0.tabbedApplet(in: $1)?.canOpenTab == true } },
        run: { context in
          context.controller?.openTab(in: context.pane)
        }
      ),
      Command(
        .splitRight, "Split Right", scope: .pane,
        isAvailable: { $0.actionsEnabled },
        run: { context in
          context.controller?.requestSplit(.row, from: context.pane)
        }
      ),
      Command(
        .splitDown, "Split Down", scope: .pane,
        isAvailable: { $0.actionsEnabled },
        run: { context in
          context.controller?.requestSplit(.column, from: context.pane)
        }
      ),
      Command(
        .close, "Close Tab or Pane", scope: .pane,
        isAvailable: { $0.actionsEnabled },
        run: { context in
          context.controller?.closeTabOrPane(context.pane)
        }
      ),
      Command(
        .selectNextTab, "Select Next Tab", scope: .pane,
        isAvailable: { $0.hasSeveralTabs },
        run: { context in
          context.controller?.stepTab(by: 1, in: context.pane)
        }
      ),
      Command(
        .selectPreviousTab, "Select Previous Tab", scope: .pane,
        isAvailable: { $0.hasSeveralTabs },
        run: { context in
          context.controller?.stepTab(by: -1, in: context.pane)
        }
      ),
      focus(.focusNextPane, "Focus Next Pane", .next),
      focus(.focusPreviousPane, "Focus Previous Pane", .previous),
      focus(.focusPaneLeft, "Focus Pane Left", .toward(.left)),
      focus(.focusPaneRight, "Focus Pane Right", .toward(.right)),
      focus(.focusPaneUp, "Focus Pane Up", .toward(.up)),
      focus(.focusPaneDown, "Focus Pane Down", .toward(.down)),
    ]
  }

  private static func focus(_ id: CommandID, _ title: String, _ move: PaneFocusMove) -> Command {
    Command(
      id, title, scope: .pane, isAvailable: { $0.actionsEnabled },
      run: { context in
        context.controller?.moveFocus(move, from: context.pane)
      })
  }

  private static func textCommands() -> [Command] {
    [
      text(.biggerText, "Bigger Text", .increaseSize),
      text(.smallerText, "Smaller Text", .decreaseSize),
      text(.actualSize, "Actual Size", .resetSize),
      text(.clearScreen, "Clear Screen", .clear),
    ]
  }

  private static func text(_ id: CommandID, _ title: String, _ action: TextAction) -> Command {
    Command(
      id, title, scope: .pane,
      isAvailable: { $0.canRun { $0.textApplet(in: $1)?.canPerform(action) == true } },
      run: { context in
        context.controller?.perform(action, in: context.pane)
      }
    )
  }

  private static func windowCommands() -> [Command] {
    [
      Command(.minimizeWindow, "Minimize", scope: .window) { context in
        context.controller?.window?.performMiniaturize(nil)
      },
      Command(.toggleMessageHistory, "Toggle Message History", scope: .window) { context in
        context.controller?.toggleHistory()
      },
      Command(
        .dismissMessage, "Dismiss Message", scope: .window,
        isAvailable: { $0.controller?.statusCenter.display?.message.level == .error },
        run: { context in
          context.controller?.statusCenter.dismissCurrent()
        }
      ),
      Command(
        .showCommandPalette, "Show Command Palette", scope: .window, listedInPalette: false,
        isAvailable: { $0.actionsEnabled },
        run: { context in
          context.controller?.showCommandPalette()
        }
      ),
    ]
  }
}

extension CommandContext {
  /// False while a sheet holds the window's attention. Pane actions wait until it is answered.
  fileprivate var actionsEnabled: Bool {
    controller?.paneActionsEnabled ?? false
  }

  fileprivate var hasSeveralTabs: Bool {
    canRun { ($0.tabbedApplet(in: $1)?.tabCount ?? 1) > 1 }
  }

  fileprivate func canRun(
    _ check: (MainWindowController, NodeID) -> Bool
  ) -> Bool {
    guard let controller, let pane, controller.paneActionsEnabled else { return false }

    return check(controller, pane)
  }
}

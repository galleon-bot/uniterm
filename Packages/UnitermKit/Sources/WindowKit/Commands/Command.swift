import PaneModel

/// A command's stable name. It is namespaced by its owner, such as `uniterm.split-right`, and it
/// is never reused for a different action. A title can change. An ID cannot.
public struct CommandID: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
  public let rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public init(stringLiteral value: String) {
    rawValue = value
  }

  public var description: String { rawValue }
}

extension CommandID {
  public static let newWindow: CommandID = "uniterm.new-window"
  public static let showSettings: CommandID = "uniterm.settings"
  public static let hideApp: CommandID = "uniterm.hide"
  public static let quit: CommandID = "uniterm.quit"
  public static let minimizeWindow: CommandID = "uniterm.minimize"
  public static let newTab: CommandID = "uniterm.new-tab"
  public static let splitRight: CommandID = "uniterm.split-right"
  public static let splitDown: CommandID = "uniterm.split-down"
  public static let close: CommandID = "uniterm.close"
  public static let selectNextTab: CommandID = "uniterm.select-next-tab"
  public static let selectPreviousTab: CommandID = "uniterm.select-previous-tab"
  public static let focusNextPane: CommandID = "uniterm.focus-next-pane"
  public static let focusPreviousPane: CommandID = "uniterm.focus-previous-pane"
  public static let focusPaneLeft: CommandID = "uniterm.focus-pane-left"
  public static let focusPaneRight: CommandID = "uniterm.focus-pane-right"
  public static let focusPaneUp: CommandID = "uniterm.focus-pane-up"
  public static let focusPaneDown: CommandID = "uniterm.focus-pane-down"
  public static let biggerText: CommandID = "uniterm.bigger-text"
  public static let smallerText: CommandID = "uniterm.smaller-text"
  public static let actualSize: CommandID = "uniterm.actual-size"
  public static let clearScreen: CommandID = "uniterm.clear-screen"
  public static let toggleMessageHistory: CommandID = "uniterm.toggle-message-history"
  public static let dismissMessage: CommandID = "uniterm.dismiss-message"
  public static let showCommandPalette: CommandID = "uniterm.show-command-palette"

  /// Cmd-1 to Cmd-8 select a tab by its number. Cmd-9 selects the last tab, as Terminal does.
  public static func selectTab(number: Int) -> CommandID {
    CommandID(number == 9 ? "uniterm.select-last-tab" : "uniterm.select-tab-\(number)")
  }
}

/// What a command acts on. It decides whether the command needs a pane that still exists.
enum CommandScope: Sendable {
  /// The app, with or without a window.
  case app

  /// The window, whatever its panes are doing.
  case window

  /// One pane of the window. A pane that is gone makes the command report that and do nothing.
  case pane
}

/// What a command runs against. The target pane is explicit and fixed when the caller built the
/// context. A run action never asks the window which pane has focus, since the palette has focus
/// while it shows.
@MainActor
struct CommandContext {
  weak var controller: MainWindowController?
  var pane: NodeID?
}

/// One thing the user can ask uniterm to do. A key binding, a menu item, and the palette run the
/// same action.
///
/// A run action is synchronous and runs on the main thread. It may start UI, such as the applet
/// chooser or a close question, and return before the user answers.
@MainActor
struct Command {
  let id: CommandID
  let title: String
  let scope: CommandScope

  /// False for a command that the palette must not list, such as the palette's own toggle or a
  /// binding that the palette's other entries already cover.
  let listedInPalette: Bool

  let isAvailable: @MainActor (CommandContext) -> Bool
  let run: @MainActor (CommandContext) -> Void

  init(
    _ id: CommandID, _ title: String, scope: CommandScope, listedInPalette: Bool = true,
    isAvailable: @escaping @MainActor (CommandContext) -> Bool = { _ in true },
    run: @escaping @MainActor (CommandContext) -> Void
  ) {
    self.id = id
    self.title = title
    self.scope = scope
    self.listedInPalette = listedInPalette
    self.isAvailable = isAvailable
    self.run = run
  }
}

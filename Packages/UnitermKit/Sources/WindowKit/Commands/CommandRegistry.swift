import PaneModel

/// What only the app can do. The app delegate supplies these, since a window has no way to open
/// another one or to show the Settings window.
public struct AppCommandHooks {
  public var newWindow: @MainActor () -> Void
  public var showSettings: @MainActor () -> Void

  public init(
    newWindow: @escaping @MainActor () -> Void = {},
    showSettings: @escaping @MainActor () -> Void = {}
  ) {
    self.newWindow = newWindow
    self.showSettings = showSettings
  }
}

/// Every command uniterm runs, shared by its key bindings, its menus, and the palette.
///
/// One registry serves the whole app, so command recency is one list for the app. Recency lives in
/// memory only. A relaunch starts with none.
@MainActor
public final class CommandRegistry {
  /// How many recently run commands the registry remembers.
  static let recencyDepth = 8

  private(set) var commands: [Command]
  private var index: [CommandID: Int] = [:]

  /// The IDs of recently run commands, newest first.
  private(set) var recency: [CommandID] = []

  public init(app: AppCommandHooks = AppCommandHooks()) {
    commands = StandardCommands.make(app: app)

    for (position, command) in commands.enumerated() {
      precondition(index[command.id] == nil, "the command \(command.id) is registered twice")
      index[command.id] = position
    }
  }

  func command(_ id: CommandID) -> Command? {
    index[id].map { commands[$0] }
  }

  /// A pane-scoped command whose pane is gone counts as available, so choosing it can say why
  /// nothing happened. Otherwise a key press would find a disabled menu item and fall through to
  /// the pane behind it.
  func isAvailable(_ id: CommandID, in context: CommandContext) -> Bool {
    guard let command = command(id) else { return false }

    if command.scope == .pane, !Self.paneExists(context) {
      return true
    }

    return command.isAvailable(context)
  }

  static func paneExists(_ context: CommandContext) -> Bool {
    guard let pane = context.pane, let controller = context.controller else { return false }

    return controller.paneArea.applet(for: pane) != nil
  }

  /// Runs a command when it is available. A run of a command the palette lists is recorded for
  /// ranking. Unlisted bindings, such as Cmd-1 to Cmd-9, would only push listed commands out of
  /// the short recency list.
  ///
  /// Returns whether it ran. A pane-scoped command whose pane is gone does not run, and the
  /// window says so.
  @discardableResult
  func run(_ id: CommandID, in context: CommandContext) -> Bool {
    guard let command = command(id), isAvailable(id, in: context) else { return false }

    if command.scope == .pane, !Self.paneExists(context) {
      context.controller?.postPaneGone(for: command.title)
      return false
    }

    command.run(context)

    if command.listedInPalette {
      remember(id)
    }

    return true
  }

  /// Runs an app command when there is no window to run it in. A command that needs a window or
  /// a pane does nothing.
  @discardableResult
  public func runWithoutWindow(_ id: CommandID) -> Bool {
    guard let command = command(id), command.scope == .app else { return false }

    return run(id, in: CommandContext(controller: nil, pane: nil))
  }

  private func remember(_ id: CommandID) {
    recency.removeAll { $0 == id }
    recency.insert(id, at: 0)

    if recency.count > Self.recencyDepth {
      recency.removeLast(recency.count - Self.recencyDepth)
    }
  }
}

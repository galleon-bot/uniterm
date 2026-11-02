import AppKit
import PaneModel

// MARK: Command palette

extension MainWindowController {
  func wireCommandPalette() {
    let palette = contentController.commandPalette

    palette.onQueryChange = { [weak self] _ in self?.refreshCommandPalette() }
    palette.onChoose = { [weak self] entry in self?.choose(entry) }
    palette.onDismiss = { [weak self] in self?.hideCommandPalette(restoringFocus: true) }
  }

  /// Shows the palette and gives its field the keyboard. The pane that has focus now becomes the
  /// target of every command the palette runs.
  func showCommandPalette() {
    guard !isPaletteVisible, paneActionsEnabled, let window else { return }

    let palette = contentController.commandPalette

    paletteTarget = paneArea.focusedPane
    palette.reset()
    refreshCommandPalette()
    palette.isHidden = false

    window.makeFirstResponder(palette.field)

    // Cmd-Z in the field undoes the field's edit, never a pane close. The field editor only
    // records edits to undo when it is told to.
    (palette.field.currentEditor() as? NSTextView)?.allowsUndo = true
  }

  /// Hides the palette. When `restoringFocus` is set, the keyboard returns to the pane that had it
  /// before the palette showed, or to the window's focused pane when that one is gone.
  ///
  /// The keyboard moves only when the palette still holds it. A sheet, the applet chooser, or a
  /// window that a command opened may have taken it, and hiding the palette never takes it back.
  func hideCommandPalette(restoringFocus: Bool) {
    guard let target = paletteTarget, let window else { return }

    let palette = contentController.commandPalette
    let holdsKeyboard = Self.holdsKeyboard(palette, in: window)

    paletteTarget = nil
    palette.isHidden = true

    if holdsKeyboard {
      window.makeFirstResponder(nil)
    }

    palette.reset()

    guard restoringFocus, holdsKeyboard, window.attachedSheet == nil else { return }

    let pane = paneArea.applet(for: target) == nil ? paneArea.focusedPane : target
    paneArea.focus(pane)
  }

  private static func holdsKeyboard(_ palette: NSView, in window: NSWindow) -> Bool {
    guard let responder = window.firstResponder else { return true }

    if responder === window { return true }

    return (responder as? NSView)?.isDescendant(of: palette) == true
  }

  /// Rebuilds the list for the current text and the current state of the window. It runs when the
  /// text changes and when the pane tree changes, so a pane that closes under the palette updates
  /// what can run.
  func refreshCommandPalette() {
    guard let target = paletteTarget else { return }

    let palette = contentController.commandPalette
    let context = CommandContext(controller: self, pane: target)
    var candidates: [PaletteCandidate] = []

    for command in commands.commands where command.listedInPalette {
      let entry = PaletteEntry(
        id: .command(command.id), kind: .command, title: command.title, detail: nil,
        isEnabled: commands.isAvailable(command.id, in: context))

      candidates.append(
        PaletteCandidate(
          entry: entry, recencyRank: commands.recency.firstIndex(of: command.id),
          order: candidates.count))
    }

    palette.setEntries(PaletteRanking.rank(candidates, query: palette.query))
  }

  /// Runs the entry the user chose. The palette hides and gives the keyboard back first, so a
  /// launcher, a sheet, or a window that the command opens ends up holding it.
  private func choose(_ entry: PaletteEntry) {
    guard let target = paletteTarget else { return }

    let context = CommandContext(controller: self, pane: target)

    hideCommandPalette(restoringFocus: true)

    switch entry.id {
    case .command(let id):
      commands.run(id, in: context)
    }
  }

  /// A mouse press outside the palette hides it, and the press then goes to what it hit. The
  /// window calls this before it handles the event.
  ///
  /// Returns whether the press hid the palette.
  func paletteWillHandleMouseDown(_ event: NSEvent) -> Bool {
    guard isPaletteVisible, event.window === window else { return false }

    let palette = contentController.commandPalette
    let point = palette.convert(event.locationInWindow, from: nil)

    guard !palette.bounds.contains(point) else { return false }

    hideCommandPalette(restoringFocus: false)
    return true
  }

  /// A press that hid the palette may land on something that takes no keyboard, such as the status
  /// bar. The keyboard then returns to the window's focused pane, so keys do not go nowhere.
  func paletteDidHandleMouseDown() {
    guard let window, !isPaletteVisible, window.attachedSheet == nil else { return }

    if window.firstResponder == nil || window.firstResponder === window {
      paneArea.focus(paneArea.focusedPane)
    }
  }
}

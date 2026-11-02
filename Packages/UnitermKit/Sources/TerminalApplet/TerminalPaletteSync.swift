import TerminalSurface
import Theme

/// Carries palette changes to the terminal engine, which updates every running session.
///
/// The app registers `apply` with the appearance controller. A failure goes to the caller, since a
/// palette that did not apply is something the user should see.
@MainActor
public final class TerminalPaletteSync {
  private let engine: any TerminalEngine
  private let onFailure: @MainActor (any Error) -> Void

  public init(engine: any TerminalEngine, onFailure: @escaping @MainActor (any Error) -> Void) {
    self.engine = engine
    self.onFailure = onFailure
  }

  public func apply(_ palette: ThemePalette) {
    do {
      try engine.apply(palette: palette)
    } catch {
      onFailure(error)
    }
  }
}

import AppKit
import AppletKit
import Theme

/// Fills a new pane until the user picks what runs there.
///
/// Choosing an applet replaces the launcher in the same pane, so the pane keeps its ID. The
/// launcher runs nothing, so it has nothing to pause and closing it asks nothing. It leaves no undo
/// entry, since there is nothing to bring back.
///
/// A saved launcher restores as a launcher. Its description is inert and carries no state, so the
/// filter and the typed command start over.
@MainActor
final class LauncherApplet: Applet {
  static let identifier = "launcher"
  static let currentVersion = 1

  let typeID = LauncherApplet.identifier
  let title = "New pane"
  let segments: [AppletSegment] = []
  let isRunningSomething = false
  weak var host: (any AppletHost)?

  let launcher = LauncherView()

  var view: NSView { launcher }

  /// Opens the choice in this launcher's pane. It throws when the choice cannot start, and the
  /// launcher shows the reason.
  var onChoose: ((AppletChoice) throws -> Void)? {
    get { launcher.onChoose }
    set { launcher.onChoose = newValue }
  }

  init() {
    launcher.onExit = { [weak self] in
      guard let self else { return }

      host?.appletDidExit(self)
    }
  }

  /// Restores a launcher from its description. The description is refused when it is another type
  /// or a newer version.
  convenience init(restoring description: AppletDescription) throws {
    guard description.type == Self.identifier else {
      throw AppletRestoreError.wrongType(expected: Self.identifier, found: description.type)
    }

    guard description.version <= Self.currentVersion else {
      throw AppletRestoreError.newerVersion(
        found: description.version, supported: Self.currentVersion)
    }

    self.init()
  }

  func start() {}
  func close() {}
  func detach() {}
  func reattach() {}

  func focus() {
    launcher.focusCurrent()
  }

  func describe() -> AppletDescription {
    AppletDescription(type: Self.identifier, version: Self.currentVersion, payload: .object([:]))
  }

  func apply(_ palette: ThemePalette) {
    launcher.apply(palette)
  }
}

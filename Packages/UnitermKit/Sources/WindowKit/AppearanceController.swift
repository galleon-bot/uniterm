import AppKit
import Preferences
import Theme

/// Owns the current palette. It follows the appearance setting and the system appearance, and
/// tells observers when the palette changes so chrome can redraw without a relaunch.
@MainActor
public final class AppearanceController {
  public private(set) var palette: ThemePalette

  private let store: SettingsStore
  private let application: NSApplication
  private var storeObservation: SettingsObservation?
  private var systemObservation: NSKeyValueObservation?
  private var observers: [UUID: @MainActor (ThemePalette) -> Void] = [:]

  public init(store: SettingsStore, application: NSApplication = .shared) {
    self.store = store
    self.application = application
    self.palette = .latte

    store.watch(.appearance)
    storeObservation = store.addObserver { [weak self] in self?.refresh() }
    systemObservation = application.observe(\.effectiveAppearance, options: [.new]) {
      [weak self] _, _ in
      Task { @MainActor in self?.refresh() }
    }

    applyApplicationAppearance()
    palette = resolvedPalette()
  }

  /// Adds a handler that runs with the new palette on every change. It also runs once immediately.
  public func addObserver(_ handler: @escaping @MainActor (ThemePalette) -> Void) -> UUID {
    let id = UUID()
    observers[id] = handler
    handler(palette)
    return id
  }

  public func removeObserver(_ id: UUID) {
    observers[id] = nil
  }

  private func refresh() {
    applyApplicationAppearance()

    let updated = resolvedPalette()
    guard updated != palette else { return }

    palette = updated
    for handler in observers.values {
      handler(updated)
    }
  }

  private func applyApplicationAppearance() {
    let wanted = Self.nsAppearance(for: store.value(of: .appearance))
    if application.appearance?.name != wanted?.name {
      application.appearance = wanted
    }
  }

  private func resolvedPalette() -> ThemePalette {
    let preference = store.value(of: .appearance)
    let systemIsDark = Self.isDark(application.effectiveAppearance)
    return ThemePalette(
      flavor: AppearanceResolver.flavor(for: preference, systemIsDark: systemIsDark))
  }

  private static func nsAppearance(for preference: AppearancePreference) -> NSAppearance? {
    switch preference {
    case .system: return nil
    case .light: return NSAppearance(named: .aqua)
    case .dark: return NSAppearance(named: .darkAqua)
    }
  }

  private static func isDark(_ appearance: NSAppearance) -> Bool {
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
  }
}

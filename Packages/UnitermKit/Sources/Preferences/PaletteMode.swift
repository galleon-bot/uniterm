/// Whether the command palette floats over the window or docks against an edge.
public enum PaletteMode: String, Sendable, CaseIterable {
  /// Hidden until the hotkey shows it over the window.
  case floating

  /// Always visible against an edge. The hotkey activates it.
  case docked
}

/// Which edge of every window a docked palette sits against.
public enum PaletteDockEdge: String, Sendable, CaseIterable {
  case top
  case bottom
}

extension SettingKey where Value == PaletteMode {
  public static var paletteMode: SettingKey<PaletteMode> {
    SettingKey(name: "paletteMode", defaultValue: .floating)
  }
}

extension SettingKey where Value == PaletteDockEdge {
  public static var paletteDockEdge: SettingKey<PaletteDockEdge> {
    SettingKey(name: "paletteDockEdge", defaultValue: .top)
  }
}

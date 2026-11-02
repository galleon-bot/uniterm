/// Which Catppuccin flavor a palette uses.
public enum ThemeFlavor: String, Sendable, CaseIterable {
  case latte
  case mocha
}

/// A named color. Applets and regions read colors by token and never carry raw values.
///
/// The names and values are Catppuccin's.
public enum ThemeToken: String, Sendable, CaseIterable {
  case rosewater, flamingo, pink, mauve, red, maroon, peach, yellow, green, teal, sky, sapphire
  case blue, lavender
  case text, subtext1, subtext0
  case overlay2, overlay1, overlay0
  case surface2, surface1, surface0
  case base, mantle, crust
}

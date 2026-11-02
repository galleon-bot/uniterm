import Preferences
import Theme

/// Picks the flavor for a preference. The system appearance matters only for `.system`.
public enum AppearanceResolver {
  public static func flavor(for preference: AppearancePreference, systemIsDark: Bool) -> ThemeFlavor
  {
    switch preference {
    case .system: return systemIsDark ? .mocha : .latte
    case .light: return .latte
    case .dark: return .mocha
    }
  }
}

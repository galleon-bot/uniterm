/// Which theme the app follows.
public enum AppearancePreference: String, Sendable, CaseIterable {
  /// Follow the system appearance: Latte when light, Mocha when dark.
  case system

  /// Always Catppuccin Latte.
  case light

  /// Always Catppuccin Mocha.
  case dark
}

extension SettingKey where Value == AppearancePreference {
  public static var appearance: SettingKey<AppearancePreference> {
    SettingKey(name: "appearance", defaultValue: .system)
  }
}

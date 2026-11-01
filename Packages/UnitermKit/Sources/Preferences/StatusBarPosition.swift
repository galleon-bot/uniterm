/// Which edge of every window the status bar docks at.
public enum StatusBarPosition: String, Sendable, CaseIterable {
  case top
  case bottom
}

extension SettingKey where Value == StatusBarPosition {
  public static var statusBarPosition: SettingKey<StatusBarPosition> {
    SettingKey(name: "statusBarPosition", defaultValue: .bottom)
  }
}

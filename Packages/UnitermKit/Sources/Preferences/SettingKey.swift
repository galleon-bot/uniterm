/// A typed key into the app's UserDefaults domain.
///
/// Values are stored as their raw strings, so `defaults write <domain> <name> -string <raw>` sets
/// them.
public struct SettingKey<Value: RawRepresentable & Sendable>: Sendable
where Value.RawValue == String {
  public let name: String
  public let defaultValue: Value

  public init(name: String, defaultValue: Value) {
    self.name = name
    self.defaultValue = defaultValue
  }
}

/// What a read of a setting found.
public enum SettingReading<Value: Sendable>: Sendable {
  case unset(fallback: Value)
  case valid(Value)

  /// The stored value is present but is not one this version understands.
  case invalid(raw: String, fallback: Value)

  /// The value to use. An invalid or missing stored value yields the default.
  public var value: Value {
    switch self {
    case .unset(let fallback): return fallback
    case .valid(let value): return value
    case .invalid(_, let fallback): return fallback
    }
  }
}

extension SettingReading: Equatable where Value: Equatable {}

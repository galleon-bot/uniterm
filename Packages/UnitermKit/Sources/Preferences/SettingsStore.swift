import Foundation

/// Typed access to the app's UserDefaults domain.
///
/// A read never writes. An invalid stored value falls back to the default in memory, and the stored
/// value stays as it was. Observers run when the domain changes, including writes from outside the
/// process, such as `defaults write`.
@MainActor
public final class SettingsStore {
  private let defaults: UserDefaults
  private var observers: [UUID: @MainActor () -> Void] = [:]
  private var keyObservers: [String: KeyObserver] = [:]

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public func reading<Value>(of key: SettingKey<Value>) -> SettingReading<Value> {
    guard let stored = defaults.object(forKey: key.name) else {
      return .unset(fallback: key.defaultValue)
    }

    if let raw = stored as? String, let value = Value(rawValue: raw) {
      return .valid(value)
    }

    return .invalid(raw: String(describing: stored), fallback: key.defaultValue)
  }

  public func value<Value>(of key: SettingKey<Value>) -> Value {
    reading(of: key).value
  }

  public func set<Value>(_ value: Value, for key: SettingKey<Value>) {
    defaults.set(value.rawValue, forKey: key.name)
  }

  /// Registers a key so that changes to it reach observers added with `addObserver`.
  /// Watching a key again does nothing.
  public func watch<Value>(_ key: SettingKey<Value>) {
    guard keyObservers[key.name] == nil else { return }

    let observer = KeyObserver(defaults: defaults, keyPath: key.name) { [weak self] in
      Task { @MainActor in self?.notify() }
    }
    keyObservers[key.name] = observer
  }

  /// Adds a handler that runs after any watched key changes. Cancel the token to unsubscribe.
  public func addObserver(_ handler: @escaping @MainActor () -> Void) -> SettingsObservation {
    let id = UUID()
    observers[id] = handler
    return SettingsObservation { [weak self] in
      self?.observers[id] = nil
    }
  }

  private func notify() {
    for handler in observers.values {
      handler()
    }
  }
}

/// Keeps a handler subscribed until it is cancelled.
@MainActor
public final class SettingsObservation {
  private var onCancel: (@MainActor () -> Void)?

  fileprivate init(onCancel: @escaping @MainActor () -> Void) {
    self.onCancel = onCancel
  }

  public func cancel() {
    onCancel?()
    onCancel = nil
  }
}

private final class KeyObserver: NSObject, @unchecked Sendable {
  private let defaults: UserDefaults
  private let keyPath: String
  private let handler: @Sendable () -> Void

  init(defaults: UserDefaults, keyPath: String, handler: @escaping @Sendable () -> Void) {
    self.defaults = defaults
    self.keyPath = keyPath
    self.handler = handler
    super.init()
    defaults.addObserver(self, forKeyPath: keyPath, options: [.new], context: nil)
  }

  deinit {
    defaults.removeObserver(self, forKeyPath: keyPath)
  }

  override func observeValue(
    forKeyPath keyPath: String?,
    of object: Any?,
    change: [NSKeyValueChangeKey: Any]?,
    context: UnsafeMutableRawPointer?
  ) {
    handler()
  }
}

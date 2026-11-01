import AppKit
import Preferences

/// One row of the Settings form for a setting with a few named values. It supplies the caption and
/// the control, and the form lays them out in its columns. A change writes the setting at once. A
/// change from outside the window, such as `defaults write`, updates the control. A stored value
/// this version does not know shows the default, and the row never writes it back.
@MainActor
final class ChoiceSettingRow<
  Value: RawRepresentable & CaseIterable & Equatable & Sendable
>: NSObject
where Value.RawValue == String, Value.AllCases: RandomAccessCollection, Value.AllCases.Index == Int
{
  let label: NSTextField
  let control = NSSegmentedControl()

  private let store: SettingsStore
  private let key: SettingKey<Value>
  private var observation: SettingsObservation?

  init(
    store: SettingsStore, key: SettingKey<Value>, caption: String, identifier: String,
    title: @escaping (Value) -> String
  ) {
    self.store = store
    self.key = key
    label = NSTextField(labelWithString: caption)
    super.init()

    control.segmentCount = Value.allCases.count
    control.trackingMode = .selectOne
    for (index, value) in Value.allCases.enumerated() {
      control.setLabel(title(value), forSegment: index)
    }
    control.target = self
    control.action = #selector(selectionChanged(_:))
    control.setAccessibilityIdentifier(identifier)

    store.watch(key)
    observation = store.addObserver { [weak self] in self?.syncFromStore() }
    syncFromStore()
  }

  isolated deinit {
    observation?.cancel()
  }

  @objc private func selectionChanged(_ sender: NSSegmentedControl) {
    let index = sender.selectedSegment
    guard Value.allCases.indices.contains(index) else { return }

    store.set(Value.allCases[index], for: key)
  }

  private func syncFromStore() {
    let current = store.value(of: key)

    if let index = Value.allCases.firstIndex(of: current) {
      control.selectedSegment = index
    }
  }
}

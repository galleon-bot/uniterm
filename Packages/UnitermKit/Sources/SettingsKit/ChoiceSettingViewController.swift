import AppKit
import Preferences

/// One row of the Settings window for a setting with a few named values. A change writes the
/// setting at once. A change from outside the window, such as `defaults write`, updates the control.
/// A stored value this version does not know shows the default, and the row never writes it back.
@MainActor
final class ChoiceSettingViewController<
  Value: RawRepresentable & CaseIterable & Equatable & Sendable
>:
  NSViewController
where Value.RawValue == String, Value.AllCases: RandomAccessCollection, Value.AllCases.Index == Int
{
  private let store: SettingsStore
  private let key: SettingKey<Value>
  private let caption: String
  private let segmentTitle: (Value) -> String
  private let controlIdentifier: String
  private let control = NSSegmentedControl()
  private var observation: SettingsObservation?

  init(
    store: SettingsStore, key: SettingKey<Value>, caption: String, identifier: String,
    title: @escaping (Value) -> String
  ) {
    self.store = store
    self.key = key
    self.caption = caption
    self.controlIdentifier = identifier
    self.segmentTitle = title
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func loadView() {
    let label = NSTextField(labelWithString: caption)
    label.alignment = .right
    label.widthAnchor.constraint(equalToConstant: 90).isActive = true

    control.segmentCount = Value.allCases.count
    control.trackingMode = .selectOne
    for (index, value) in Value.allCases.enumerated() {
      control.setLabel(segmentTitle(value), forSegment: index)
    }
    control.target = self
    control.action = #selector(selectionChanged(_:))
    control.setAccessibilityIdentifier(controlIdentifier)

    let row = NSStackView(views: [label, control])
    row.orientation = .horizontal
    row.alignment = .firstBaseline
    row.spacing = 12

    view = row

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

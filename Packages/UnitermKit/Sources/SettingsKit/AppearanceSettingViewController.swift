import AppKit
import Preferences

/// The Appearance row of the Settings window. A change writes the setting at once. A change from
/// outside the window, such as `defaults write`, updates the control.
@MainActor
final class AppearanceSettingViewController: NSViewController {
  private let store: SettingsStore
  private let control = NSSegmentedControl()
  private var observation: SettingsObservation?

  init(store: SettingsStore) {
    self.store = store
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func loadView() {
    let label = NSTextField(labelWithString: "Appearance:")

    control.segmentCount = AppearancePreference.allCases.count
    control.trackingMode = .selectOne
    for (index, preference) in AppearancePreference.allCases.enumerated() {
      control.setLabel(Self.title(for: preference), forSegment: index)
    }
    control.target = self
    control.action = #selector(selectionChanged(_:))
    control.setAccessibilityIdentifier("appearance-control")

    let row = NSStackView(views: [label, control])
    row.orientation = .horizontal
    row.alignment = .firstBaseline
    row.spacing = 12
    row.translatesAutoresizingMaskIntoConstraints = false

    let container = NSView()
    container.addSubview(row)
    NSLayoutConstraint.activate([
      row.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
      row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
      row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
      row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
    ])

    view = container

    store.watch(.appearance)
    observation = store.addObserver { [weak self] in self?.syncFromStore() }
    syncFromStore()
  }

  isolated deinit {
    observation?.cancel()
  }

  @objc private func selectionChanged(_ sender: NSSegmentedControl) {
    let index = sender.selectedSegment
    guard AppearancePreference.allCases.indices.contains(index) else { return }
    store.set(AppearancePreference.allCases[index], for: .appearance)
  }

  private func syncFromStore() {
    let current = store.value(of: .appearance)
    if let index = AppearancePreference.allCases.firstIndex(of: current) {
      control.selectedSegment = index
    }
  }

  private static func title(for preference: AppearancePreference) -> String {
    switch preference {
    case .system: return "System"
    case .light: return "Light"
    case .dark: return "Dark"
    }
  }
}

import AppKit
import Preferences

/// The Settings window's content: one row for each global setting.
@MainActor
final class SettingsViewController: NSViewController {
  private let appearance: ChoiceSettingRow<AppearancePreference>
  private let statusBarPosition: ChoiceSettingRow<StatusBarPosition>

  init(store: SettingsStore) {
    appearance = ChoiceSettingRow(
      store: store, key: .appearance, caption: "Appearance:", identifier: "appearance-control"
    ) { preference in
      switch preference {
      case .system: return "System"
      case .light: return "Light"
      case .dark: return "Dark"
      }
    }

    statusBarPosition = ChoiceSettingRow(
      store: store, key: .statusBarPosition, caption: "Status bar:",
      identifier: "status-bar-position-control"
    ) { position in
      switch position {
      case .top: return "Top"
      case .bottom: return "Bottom"
      }
    }

    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  /// A two-column form. Captions are right-aligned and end at one edge. Controls start at the
  /// next edge. The window sizes itself to the form plus the standard margin.
  override func loadView() {
    let grid = NSGridView(views: [
      [appearance.label, appearance.control],
      [statusBarPosition.label, statusBarPosition.control],
    ])
    grid.translatesAutoresizingMaskIntoConstraints = false
    grid.rowSpacing = 12
    grid.columnSpacing = 8
    grid.column(at: 0).xPlacement = .trailing
    grid.column(at: 1).xPlacement = .leading
    grid.rowAlignment = .firstBaseline

    let content = NSView()
    content.addSubview(grid)

    let margin: CGFloat = 20
    NSLayoutConstraint.activate([
      grid.topAnchor.constraint(equalTo: content.topAnchor, constant: margin),
      grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: margin),
      grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -margin),
      grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -margin),
    ])

    view = content
  }
}

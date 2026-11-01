import AppKit
import Preferences

/// The Settings window's content: one row for each global setting.
@MainActor
final class SettingsViewController: NSViewController {
  private let appearance: ChoiceSettingViewController<AppearancePreference>
  private let statusBarPosition: ChoiceSettingViewController<StatusBarPosition>

  init(store: SettingsStore) {
    appearance = ChoiceSettingViewController(
      store: store, key: .appearance, caption: "Appearance:", identifier: "appearance-control"
    ) { preference in
      switch preference {
      case .system: return "System"
      case .light: return "Light"
      case .dark: return "Dark"
      }
    }

    statusBarPosition = ChoiceSettingViewController(
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

  override func loadView() {
    addChild(appearance)
    addChild(statusBarPosition)

    let column = NSStackView(views: [appearance.view, statusBarPosition.view])
    column.orientation = .vertical
    column.alignment = .leading
    column.spacing = 16
    column.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)

    view = column
  }
}

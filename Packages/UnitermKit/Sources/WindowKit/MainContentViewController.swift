import AppKit
import Theme

/// The window's content. It lays out the regions: the pane area fills the window, and the
/// docked regions sit against the top or the bottom edge.
///
/// Everything lies inside the safe area, so no region covers the traffic lights. A region docked
/// at the top starts below the title bar, which leaves the title bar free to drag the window.
@MainActor
final class MainContentViewController: NSViewController {
  private struct Docked {
    var role: RegionRole
    var view: NSView
    var thickness: CGFloat
    var edge: DockEdge
  }

  private let chrome = ChromeView()
  private let paneView: NSView
  private var docked: [Docked] = []
  private var regionConstraints: [NSLayoutConstraint] = []
  private let initialStatusBarEdge: DockEdge

  let statusBar = StatusBarView()
  let history = HistoryPanelView()

  /// Runs after every layout pass, since the safe area that sets the window's minimum size can
  /// change with it.
  var onLayout: (() -> Void)?

  /// The height of everything in the window that is not the pane area. The history floats, so it
  /// does not count.
  var chromeHeight: CGFloat {
    chrome.safeAreaInsets.top + docked.reduce(0) { $0 + $1.thickness }
  }

  init(paneView: NSView, statusBarEdge: DockEdge) {
    self.paneView = paneView
    initialStatusBarEdge = statusBarEdge
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func loadView() {
    chrome.setAccessibilityElement(true)
    chrome.setAccessibilityRole(.group)
    chrome.setAccessibilityIdentifier("content-area")

    paneView.translatesAutoresizingMaskIntoConstraints = false
    chrome.addSubview(paneView)

    history.translatesAutoresizingMaskIntoConstraints = false
    chrome.addSubview(history)

    view = chrome

    install(statusBar, role: .statusBar, thickness: StatusBarView.height, at: initialStatusBarEdge)
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    onLayout?()
  }

  func apply(_ palette: ThemePalette) {
    chrome.apply(palette)
    statusBar.apply(palette)
    history.apply(palette)
  }

  /// The edge a docked region sits against.
  func edge(of role: RegionRole) -> DockEdge? {
    docked.first { $0.role == role }?.edge
  }

  /// Docks a region that the window does not hold yet.
  func install(_ region: NSView, role: RegionRole, thickness: CGFloat, at edge: DockEdge) {
    precondition(!docked.contains { $0.role == role }, "a region is installed once")

    region.translatesAutoresizingMaskIntoConstraints = false
    chrome.addSubview(region)
    docked.append(Docked(role: role, view: region, thickness: thickness, edge: edge))
    layoutRegions()
  }

  /// Moves an installed region to another edge. The view is kept, so a move changes where the
  /// region sits and nothing it shows.
  func move(_ role: RegionRole, to edge: DockEdge) {
    guard let index = docked.firstIndex(where: { $0.role == role }) else { return }

    docked[index].edge = edge
    layoutRegions()
  }

  func setHistoryVisible(_ visible: Bool) {
    history.isHidden = !visible
  }

  private func layoutRegions() {
    NSLayoutConstraint.deactivate(regionConstraints)
    regionConstraints = []

    let guide = chrome.safeAreaLayoutGuide
    let order = RegionStack.order(docked.map { RegionPlacement(role: $0.role, edge: $0.edge) })

    var topAnchor = guide.topAnchor
    for role in order.top {
      guard let region = docked.first(where: { $0.role == role }) else { continue }

      regionConstraints += place(region, in: guide)
      regionConstraints.append(region.view.topAnchor.constraint(equalTo: topAnchor))
      topAnchor = region.view.bottomAnchor
    }

    var bottomAnchor = guide.bottomAnchor
    for role in order.bottom {
      guard let region = docked.first(where: { $0.role == role }) else { continue }

      regionConstraints += place(region, in: guide)
      regionConstraints.append(region.view.bottomAnchor.constraint(equalTo: bottomAnchor))
      bottomAnchor = region.view.topAnchor
    }

    regionConstraints += [
      paneView.topAnchor.constraint(equalTo: topAnchor),
      paneView.bottomAnchor.constraint(equalTo: bottomAnchor),
      paneView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
      paneView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
      history.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
      history.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
      history.heightAnchor.constraint(equalToConstant: HistoryPanelView.height),
    ]

    // The history grows away from the status bar, over the pane area.
    if let bar = docked.first(where: { $0.role == .statusBar }) {
      switch bar.edge {
      case .top:
        regionConstraints.append(history.topAnchor.constraint(equalTo: bar.view.bottomAnchor))

      case .bottom:
        regionConstraints.append(history.bottomAnchor.constraint(equalTo: bar.view.topAnchor))
      }
    }

    NSLayoutConstraint.activate(regionConstraints)
    chrome.needsLayout = true
  }

  private func place(_ region: Docked, in guide: NSLayoutGuide) -> [NSLayoutConstraint] {
    [
      region.view.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
      region.view.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
      region.view.heightAnchor.constraint(equalToConstant: region.thickness),
    ]
  }
}

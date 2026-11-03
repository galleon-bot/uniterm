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

  /// A floating palette's distance from the top of the pane area, and the smallest side margin of
  /// either kind.
  static let paletteTopInset: CGFloat = 12
  static let paletteMargin: CGFloat = 16

  /// The gap between the palette's field and its results.
  static let paletteResultsGap: CGFloat = 4

  /// A docked palette's strip holds the field, with 6 points between the field and the window's
  /// side of the strip and 2 on the pane side. The results open from the pane side.
  static let dockedPaletteOuterInset: CGFloat = 6
  static let dockedPaletteInnerInset: CGFloat = 2

  static var dockedPaletteThickness: CGFloat {
    dockedPaletteOuterInset + CommandPaletteView.fieldHeight + dockedPaletteInnerInset
  }

  private let chrome = ChromeView()
  private let paneView: NSView
  private var docked: [Docked] = []
  private var regionConstraints: [NSLayoutConstraint] = []
  private let initialStatusBarEdge: DockEdge
  private let initialPalette: PalettePlacement.Value
  private var paletteConstraints: [NSLayoutConstraint] = []

  let statusBar = StatusBarView()
  let history = HistoryPanelView()
  let commandPalette = CommandPaletteView()
  let paletteStrip = PaletteDockStrip()

  /// Where the palette is now.
  private(set) var palettePlacement: PalettePlacement.Value

  /// Runs after every layout pass, since the safe area that sets the window's minimum size can
  /// change with it.
  var onLayout: (() -> Void)?

  /// The height of everything in the window that is not the pane area. The history floats, so it
  /// does not count.
  var chromeHeight: CGFloat {
    chrome.safeAreaInsets.top + docked.reduce(0) { $0 + $1.thickness }
  }

  init(paneView: NSView, statusBarEdge: DockEdge, palette: PalettePlacement.Value) {
    self.paneView = paneView
    initialStatusBarEdge = statusBarEdge
    initialPalette = palette
    palettePlacement = palette
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

    commandPalette.translatesAutoresizingMaskIntoConstraints = false
    paletteStrip.translatesAutoresizingMaskIntoConstraints = false
    chrome.addSubview(commandPalette.results)
    setPalette(initialPalette)
  }

  /// Puts the palette where `placement` says. A floating palette sits near the top of the pane
  /// area. A docked one sits in a strip against an edge, and the strip counts toward the window's
  /// minimum size like any docked region.
  ///
  /// The field and the results are the same views either way. Only where they sit changes.
  func setPalette(_ placement: PalettePlacement.Value) {
    NSLayoutConstraint.deactivate(paletteConstraints)
    paletteConstraints = []
    palettePlacement = placement

    commandPalette.removeFromSuperview()

    switch placement.mode {
    case .floating:
      uninstall(.commandPalette)
      chrome.addSubview(commandPalette)

    case .docked:
      paletteStrip.addSubview(commandPalette)

      if edge(of: .commandPalette) == nil {
        install(
          paletteStrip, role: .commandPalette, thickness: Self.dockedPaletteThickness,
          at: placement.edge)
      } else {
        move(.commandPalette, to: placement.edge)
      }
    }

    commandPalette.present(as: placement.mode == .floating ? .floating : .docked)

    // The results draw above every region, and so above a strip that was installed after them.
    chrome.addSubview(commandPalette.results, positioned: .above, relativeTo: nil)

    paletteConstraints = fieldConstraints(for: placement) + resultsConstraints(for: placement)
    NSLayoutConstraint.activate(paletteConstraints)
    chrome.needsLayout = true
  }

  /// The field is never wider than its fixed width. It fills the window's width less a margin on
  /// each side when the window is narrower. The fill is weak, so the palette never sets how small
  /// the window can get.
  private func fieldConstraints(for placement: PalettePlacement.Value) -> [NSLayoutConstraint] {
    let palette = commandPalette
    let height = palette.heightAnchor.constraint(equalToConstant: CommandPaletteView.fieldHeight)
    let limit = palette.widthAnchor.constraint(lessThanOrEqualToConstant: CommandPaletteView.width)

    let host: NSView
    let fill: NSLayoutConstraint

    switch placement.mode {
    case .floating:
      host = chrome
      fill = palette.widthAnchor.constraint(
        equalTo: chrome.safeAreaLayoutGuide.widthAnchor, constant: -2 * Self.paletteMargin)

    case .docked:
      host = paletteStrip
      fill = palette.widthAnchor.constraint(
        equalTo: paletteStrip.widthAnchor, constant: -2 * Self.paletteMargin)
    }

    fill.priority = NSLayoutConstraint.Priority(10)

    var constraints = [limit, fill, height]

    switch placement.mode {
    case .floating:
      constraints += [
        palette.centerXAnchor.constraint(equalTo: chrome.safeAreaLayoutGuide.centerXAnchor),
        palette.topAnchor.constraint(equalTo: paneView.topAnchor, constant: Self.paletteTopInset),
      ]

    case .docked:
      constraints.append(palette.centerXAnchor.constraint(equalTo: host.centerXAnchor))

      switch placement.edge {
      case .top:
        constraints.append(
          palette.topAnchor.constraint(
            equalTo: host.topAnchor, constant: Self.dockedPaletteOuterInset))

      case .bottom:
        constraints.append(
          palette.bottomAnchor.constraint(
            equalTo: host.bottomAnchor, constant: -Self.dockedPaletteOuterInset))
      }
    }

    return constraints
  }

  /// The results line up with the field and open away from the docked edge, down for a floating
  /// palette. They never leave the pane area, so a short window shortens the list. Their height is
  /// a preference that yields to that bound.
  private func resultsConstraints(for placement: PalettePlacement.Value) -> [NSLayoutConstraint] {
    let results = commandPalette.results
    let palette = commandPalette

    var constraints = [
      results.leadingAnchor.constraint(equalTo: palette.leadingAnchor),
      results.trailingAnchor.constraint(equalTo: palette.trailingAnchor),
    ]

    if placement.mode == .docked, placement.edge == .bottom {
      constraints += [
        results.bottomAnchor.constraint(
          equalTo: palette.topAnchor, constant: -Self.paletteResultsGap),
        results.topAnchor.constraint(greaterThanOrEqualTo: paneView.topAnchor),
      ]
    } else {
      constraints += [
        results.topAnchor.constraint(
          equalTo: palette.bottomAnchor, constant: Self.paletteResultsGap),
        results.bottomAnchor.constraint(lessThanOrEqualTo: paneView.bottomAnchor),
      ]
    }

    return constraints
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    onLayout?()
  }

  func apply(_ palette: ThemePalette) {
    chrome.apply(palette)
    statusBar.apply(palette)
    history.apply(palette)
    commandPalette.apply(palette)
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

  /// Takes an installed region out of the window. Its view is kept for a later install.
  func uninstall(_ role: RegionRole) {
    guard let index = docked.firstIndex(where: { $0.role == role }) else { return }

    docked.remove(at: index).view.removeFromSuperview()
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

    // The history grows away from the status bar, over the pane area. It starts at the pane area's
    // edge, so a docked palette on the same edge is not covered by it.
    if let bar = docked.first(where: { $0.role == .statusBar }) {
      switch bar.edge {
      case .top:
        regionConstraints.append(history.topAnchor.constraint(equalTo: paneView.topAnchor))

      case .bottom:
        regionConstraints.append(history.bottomAnchor.constraint(equalTo: paneView.bottomAnchor))
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

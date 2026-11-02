import AppKit
import AppletKit
import Theme

/// Stands in for any applet. It holds one tab and cannot open another, as a plain applet would,
/// until a test says otherwise.
@MainActor
final class FakeApplet: TabbedApplet, TextActionApplet {
  let typeID = "fake"
  let view = NSView()
  var title = "Fake"
  var segments: [AppletSegment] = []
  var isRunningSomething = false
  weak var host: (any AppletHost)?

  /// What the applet reports as its current directory. Nil says nothing.
  var currentDirectory: String?
  var started = false
  var closed = false
  var detachCount = 0
  var reattachCount = 0

  /// What a dialog calls the running parts. Without it, a running applet names its title.
  var labels: [String]?

  var runningLabels: [String] {
    isRunningSomething ? (labels ?? [title]) : []
  }

  /// Each tab's ID and title, in order. A test sets `tabCount` or `tabTitles` and the tabs follow.
  private var tabIDs: [AppletTabID] = [.make()]
  var tabTitles: [String] = []
  var tabDetails: [Int: [String]] = [:]

  var tabCount: Int {
    get { tabIDs.count }
    set {
      while tabIDs.count < newValue { tabIDs.append(.make()) }
      tabIDs.removeLast(tabIDs.count - max(newValue, 1))
    }
  }

  var selectedTabIndex = 0

  /// The first tab shows the applet's title, and the rest show their own or a numbered name.
  var publishedTabs: AppletTabList {
    let tabs = tabIDs.enumerated().map { index, id in
      let title =
        index < tabTitles.count
        ? tabTitles[index] : (index == 0 ? self.title : "\(self.title) \(index + 1)")
      return AppletTab(id: id, title: title, details: tabDetails[index] ?? [])
    }

    return AppletTabList(
      first: tabs[0], rest: Array(tabs.dropFirst()), selected: tabIDs[selectedTabIndex])
  }

  /// A tab that closed without telling the host, so the palette's list is stale.
  func removeTab(at index: Int) {
    tabIDs.remove(at: index)
    selectedTabIndex = min(selectedTabIndex, tabIDs.count - 1)
  }

  /// Every tab becomes a new tab, as when an applet is restored from its description.
  func renewTabIDs() {
    tabIDs = tabIDs.map { _ in .make() }
  }

  /// The ID of the tab at an index, for a test that aims at it.
  func tabID(_ index: Int) -> AppletTabID { tabIDs[index] }

  /// Tells the host the tab list changed, as an applet would.
  func tabsChanged() { host?.appletTabsDidChange(self) }

  func selectTab(id: AppletTabID) -> Bool {
    guard let index = tabIDs.firstIndex(of: id) else { return false }

    selectedTabIndex = index
    return true
  }

  var canOpenTab = false
  var openedTabs = 0
  var tabsClosed = 0

  func openTab() {
    openedTabs += 1
    tabIDs.append(.make())
    selectedTabIndex = tabCount - 1
  }

  func selectTab(at index: Int) {
    guard (0..<tabCount).contains(index) else { return }

    selectedTabIndex = index
  }

  func closeSelectedTab() async -> Bool {
    guard tabCount > 1 else { return false }

    tabsClosed += 1
    tabIDs.remove(at: selectedTabIndex)
    tabTitles = tabTitles.enumerated().filter { $0.offset != selectedTabIndex }.map(\.element)
    selectedTabIndex = min(selectedTabIndex, tabCount - 1)
    return true
  }

  /// The text actions the applet performed, oldest first.
  var textActions: [TextAction] = []
  var canPerformText = true

  func canPerform(_ action: TextAction) -> Bool { canPerformText }

  func perform(_ action: TextAction) { textActions.append(action) }

  func start() { started = true }
  func close() { closed = true }
  func detach() { detachCount += 1 }
  func reattach() { reattachCount += 1 }
  var focusCount = 0

  func focus() { focusCount += 1 }

  /// The palettes the host handed over, oldest first.
  var palettes: [ThemePalette] = []

  func apply(_ palette: ThemePalette) { palettes.append(palette) }

  /// When set, the description stays fixed while the title changes, as a terminal's does.
  var fixedDescription: AppletDescription?

  /// The description carries the title, so a test can tell which applet a reopened pane came from.
  func describe() -> AppletDescription {
    fixedDescription ?? AppletDescription(type: "fake", version: 1, payload: .string(title))
  }
}

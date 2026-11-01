import AppKit
import AppletKit

/// Stands in for any applet. It holds one tab and cannot open another, as a plain applet would,
/// until a test says otherwise.
@MainActor
final class FakeApplet: TabbedApplet {
  let typeID = "fake"
  let view = NSView()
  var title = "Fake"
  var segments: [AppletSegment] = []
  var isRunningSomething = false
  weak var host: (any AppletHost)?
  var started = false
  var closed = false

  var tabCount = 1
  var selectedTabIndex = 0
  var canOpenTab = false
  var openedTabs = 0
  var tabsClosed = 0

  func openTab() {
    openedTabs += 1
    tabCount += 1
    selectedTabIndex = tabCount - 1
  }

  func selectTab(at index: Int) {
    guard (0..<tabCount).contains(index) else { return }

    selectedTabIndex = index
  }

  func closeSelectedTab() async -> Bool {
    guard tabCount > 1 else { return false }

    tabsClosed += 1
    tabCount -= 1
    selectedTabIndex = min(selectedTabIndex, tabCount - 1)
    return true
  }

  func start() { started = true }
  func close() { closed = true }
  func detach() {}
  func reattach() {}
  func focus() {}
  func describe() -> AppletDescription {
    AppletDescription(type: "fake", version: 1, payload: .null)
  }
}

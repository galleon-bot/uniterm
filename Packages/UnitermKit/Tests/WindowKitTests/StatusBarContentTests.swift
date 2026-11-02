import AppletKit
import Preferences
import StatusKit
import XCTest

@testable import WindowKit

/// Every expected value is written out by hand from the rules in the type, never read back from it.
final class StatusBarContentTests: XCTestCase {
  private func display(
    _ level: StatusLevel, _ source: StatusSource, _ text: String, errorsBefore: Int = 0
  ) -> StatusDisplay? {
    var queue = StatusQueue()

    for index in 0..<errorsBefore {
      queue.post(level: .error, source: .uniterm, text: "old\(index)", at: 0)
    }

    queue.post(level: level, source: source, text: text, at: 0)
    queue.advance(at: 1.5)

    return queue.current
  }

  /// Catches a bar with no message area while idle.
  func testAnIdleBarKeepsAnEmptyMessageArea() {
    let segments = StatusBarContent.segments(display: nil, hasUnseenError: false, applet: [])

    XCTAssertEqual(
      segments, [BarSegment(id: .message, symbolName: nil, text: "", tone: .normal)])
  }

  /// Catches a window slot that sits among the applet's slots, or is displaced by an error and its
  /// indicators. The window's slots come first in a fixed order, and the applet's follow.
  func testTheWindowsOwnSlotsPrecedeTheApplets() {
    let segments = StatusBarContent.segments(
      display: display(.error, .uniterm, "boom"), hasUnseenError: true,
      applet: [AppletSegment(text: "tmp")])

    XCTAssertEqual(segments.map(\.id), [.message, .dismiss, .unseenError, .applet(0)])
  }

  /// Catches a message shown without its source, or with the wrong icon or tone for its level.
  func testTheMessageAreaShowsSourceTextAndLevelStyle() {
    let info = StatusBarContent.message(display(.info, .pane(id: 7, name: "zsh"), "done"))
    XCTAssertEqual(info.text, "zsh: done")
    XCTAssertEqual(info.symbolName, "info.circle")
    XCTAssertEqual(info.tone, .normal)

    let warning = StatusBarContent.message(display(.warning, .applet(name: "git"), "dirty"))
    XCTAssertEqual(warning.text, "git: dirty")
    XCTAssertEqual(warning.symbolName, "exclamationmark.triangle")
    XCTAssertEqual(warning.tone, .warning)

    let error = StatusBarContent.message(display(.error, .script(name: "init"), "failed"))
    XCTAssertEqual(error.text, "init: failed")
    XCTAssertEqual(error.symbolName, "xmark.octagon")
    XCTAssertEqual(error.tone, .error)
  }

  /// Catches a folded error backlog that loses its count.
  ///
  /// The first of four errors is on the bar. The next two queue behind it and fold into the
  /// fourth, so the fourth shows with a count of 2.
  func testFoldedErrorsShowTheirCount() {
    let folded = display(.error, .uniterm, "boom", errorsBefore: 3)

    XCTAssertEqual(
      StatusBarContent.message(folded).text, "uniterm: boom  (+2 more errors)")
  }

  /// Catches segments in the wrong order, or an indicator without an error.
  func testSegmentsAreTheWindowsThenTheApplets() {
    let applet = [
      AppletSegment(symbolName: "folder", text: "tmp"),
      AppletSegment(symbolName: "xmark.circle", text: "2", style: .error),
      AppletSegment(text: "INSERT", style: .emphasized),
    ]

    let with = StatusBarContent.segments(display: nil, hasUnseenError: true, applet: applet)
    XCTAssertEqual(
      with.map(\.id), [.message, .unseenError, .applet(0), .applet(1), .applet(2)])
    XCTAssertEqual(with[1].symbolName, "exclamationmark.circle.fill")
    XCTAssertNil(with[1].text)
    XCTAssertEqual(with[1].tone, .error)
    XCTAssertEqual(with[1].accessibilityLabel, "Unseen errors")
    XCTAssertEqual(with.dropFirst(2).map(\.tone), [.normal, .error, .emphasized])
    XCTAssertEqual(with.dropFirst(2).map(\.text), ["tmp", "2", "INSERT"])

    let without = StatusBarContent.segments(display: nil, hasUnseenError: false, applet: applet)
    XCTAssertEqual(without.map(\.id), [.message, .applet(0), .applet(1), .applet(2)])
  }

  /// Catches a dismiss control on a message that clears itself, or none on an error.
  func testOnlyAnErrorOffersADismissControl() {
    let error = StatusBarContent.segments(
      display: display(.error, .uniterm, "boom"), hasUnseenError: true, applet: [])
    XCTAssertEqual(error.map(\.id), [.message, .dismiss, .unseenError])
    XCTAssertEqual(error[1].accessibilityLabel, "Dismiss message")

    for level in [StatusLevel.info, .warning] {
      let other = StatusBarContent.segments(
        display: display(level, .uniterm, "x"), hasUnseenError: false, applet: [])
      XCTAssertEqual(other.map(\.id), [.message])
    }
  }

  /// Catches history lines that drop the level, or put the source after the text.
  func testHistoryLinesCarryLevelSourceAndText() {
    var queue = StatusQueue()
    let message = queue.post(
      level: .warning, source: .pane(id: 3, name: "vim"), text: "swap file", at: 0)

    XCTAssertEqual(StatusBarContent.historyLine(message), "warning  vim: swap file")
  }

  // MARK: Regions

  /// Catches a region that lands on the wrong edge's list.
  func testRegionsStackAgainstTheirOwnEdge() {
    let bottom = RegionStack.order([RegionPlacement(role: .statusBar, edge: .bottom)])
    XCTAssertEqual(bottom.top, [])
    XCTAssertEqual(bottom.bottom, [.statusBar])

    let top = RegionStack.order([RegionPlacement(role: .statusBar, edge: .top)])
    XCTAssertEqual(top.top, [.statusBar])
    XCTAssertEqual(top.bottom, [])
  }

  /// Catches a dock edge that does not follow the setting.
  func testTheDockEdgeFollowsTheSetting() {
    XCTAssertEqual(DockEdge(.top), .top)
    XCTAssertEqual(DockEdge(.bottom), .bottom)
  }
}

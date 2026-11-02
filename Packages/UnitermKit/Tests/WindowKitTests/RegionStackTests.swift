import XCTest

@testable import WindowKit

final class RegionStackTests: XCTestCase {
  /// Catches a stack that depends on install order. The status bar takes the window's edge and the
  /// palette sits inward, whichever was installed first.
  func testTheStatusBarIsOutermostAndThePaletteSitsInwardOnOneEdge() {
    for edge in [DockEdge.top, .bottom] {
      let barFirst = RegionStack.order([
        RegionPlacement(role: .statusBar, edge: edge),
        RegionPlacement(role: .commandPalette, edge: edge),
      ])
      let paletteFirst = RegionStack.order([
        RegionPlacement(role: .commandPalette, edge: edge),
        RegionPlacement(role: .statusBar, edge: edge),
      ])

      for order in [barFirst, paletteFirst] {
        let list = edge == .top ? order.top : order.bottom
        XCTAssertEqual(list, [.statusBar, .commandPalette])
        XCTAssertTrue((edge == .top ? order.bottom : order.top).isEmpty)
      }
    }
  }

  /// Catches regions on different edges that interfere with each other.
  func testRegionsOnDifferentEdgesStayApart() {
    let order = RegionStack.order([
      RegionPlacement(role: .statusBar, edge: .bottom),
      RegionPlacement(role: .commandPalette, edge: .top),
    ])

    XCTAssertEqual(order.top, [.commandPalette])
    XCTAssertEqual(order.bottom, [.statusBar])
  }
}

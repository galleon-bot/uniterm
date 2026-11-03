import AppKit
import XCTest

@testable import WindowKit

/// Where a pane puts its applet's view.
@MainActor
final class PaneFrameViewTests: XCTestCase {
  /// Catches an applet frame that is not finite. A pane starts at zero size, before the first
  /// layout. Insetting zero bounds by the gutter gives the null rect, whose origin is infinite.
  /// AppKit then clamps that frame into a constraint and logs a warning on every launch.
  func testAPaneSmallerThanItsGutterGivesTheAppletAFiniteEmptyFrame() {
    for bounds in [NSRect.zero, NSRect(x: 0, y: 0, width: 3, height: 1)] {
      let frame = PaneFrameView.appletFrame(in: bounds)

      XCTAssertFalse(frame.isNull, "\(bounds)")
      XCTAssertTrue(frame.origin.x.isFinite && frame.origin.y.isFinite, "\(bounds)")
      XCTAssertEqual(frame.size, .zero, "\(bounds)")
    }
  }

  /// Catches a gutter that is lost once the pane has room. A 100 by 50 pane holds its applet 2
  /// points in from every edge.
  func testAPaneWithRoomInsetsItsAppletByTheGutter() {
    XCTAssertEqual(
      PaneFrameView.appletFrame(in: NSRect(x: 0, y: 0, width: 100, height: 50)),
      NSRect(x: 2, y: 2, width: 96, height: 46))
  }
}

import CoreGraphics
import XCTest

@testable import LayoutKit

final class FrameClampTests: XCTestCase {
  private let main = ScreenArea(
    frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
    visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))

  private let side = ScreenArea(
    frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
    visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1055))

  func testAFrameInsideAScreenStays() {
    let frame = CGRect(x: 100, y: 100, width: 800, height: 600)

    XCTAssertEqual(FrameClamp.clamp(frame, savedScreen: nil, screens: [main]), frame)
  }

  /// The saved screen was to the right and is unplugged. The window moves fully onto the screen
  /// that is left, and keeps its size.
  func testAWindowFromAGoneScreenLandsFullyOnAVisibleScreen() {
    let frame = CGRect(x: 2000, y: 300, width: 800, height: 600)

    let result = FrameClamp.clamp(frame, savedScreen: side.frame, screens: [main])

    XCTAssertTrue(main.visibleFrame.contains(result), "\(result)")
    XCTAssertEqual(result.size, frame.size)
  }

  func testAWindowLargerThanTheScreenIsCutToFit() {
    let frame = CGRect(x: -50, y: -50, width: 3000, height: 2000)

    let result = FrameClamp.clamp(frame, savedScreen: nil, screens: [main])

    XCTAssertEqual(result, main.visibleFrame)
  }

  /// The saved screen is still attached, so a window that hangs off it moves back onto that
  /// screen and not onto the main one.
  func testASavedScreenThatExistsIsPreferred() {
    let frame = CGRect(x: 3000, y: 900, width: 800, height: 600)

    let result = FrameClamp.clamp(frame, savedScreen: side.frame, screens: [main, side])

    XCTAssertTrue(side.visibleFrame.contains(result), "\(result)")
  }

  func testTheMinimumSizeGrowsAFrameButTheScreenStillWins() {
    let frame = CGRect(x: 0, y: 0, width: 300, height: 200)

    XCTAssertEqual(
      FrameClamp.clamp(
        frame, savedScreen: nil, screens: [main], minimumSize: CGSize(width: 600, height: 400)
      ).size,
      CGSize(width: 600, height: 400))

    XCTAssertEqual(
      FrameClamp.clamp(
        frame, savedScreen: nil, screens: [main], minimumSize: CGSize(width: 5000, height: 4000)
      ).size,
      main.visibleFrame.size)
  }

  func testWithNoScreensTheFrameIsUnchanged() {
    let frame = CGRect(x: 1, y: 2, width: 3, height: 4)

    XCTAssertEqual(FrameClamp.clamp(frame, savedScreen: nil, screens: []), frame)
  }
}

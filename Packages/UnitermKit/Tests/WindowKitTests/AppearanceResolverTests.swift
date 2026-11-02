import Preferences
import Theme
import XCTest

@testable import WindowKit

final class AppearanceResolverTests: XCTestCase {
  /// Catches a swapped mapping. System follows the OS, and an explicit choice ignores it.
  func testResolution() {
    XCTAssertEqual(AppearanceResolver.flavor(for: .system, systemIsDark: false), .latte)
    XCTAssertEqual(AppearanceResolver.flavor(for: .system, systemIsDark: true), .mocha)
    XCTAssertEqual(AppearanceResolver.flavor(for: .light, systemIsDark: true), .latte)
    XCTAssertEqual(AppearanceResolver.flavor(for: .dark, systemIsDark: false), .mocha)
  }
}

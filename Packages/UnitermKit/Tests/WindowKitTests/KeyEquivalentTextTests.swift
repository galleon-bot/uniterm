import AppKit
import XCTest

@testable import WindowKit

final class KeyEquivalentTextTests: XCTestCase {
  /// Catches a placeholder that names the wrong key after a remap, or the modifiers out of the
  /// menu's own order.
  func testSpellsModifiersInMenuOrder() {
    XCTAssertEqual(
      KeyEquivalentText.spell(key: "p", modifiers: [.command, .shift]), "\u{21E7}\u{2318}P")
    XCTAssertEqual(
      KeyEquivalentText.spell(key: "o", modifiers: [.command, .shift, .option, .control]),
      "\u{2303}\u{2325}\u{21E7}\u{2318}O")
    XCTAssertEqual(KeyEquivalentText.spell(key: "\u{8}", modifiers: [.command]), "\u{2318}\u{232B}")
  }

  func testAnItemWithNoKeyHasNoSpelling() {
    XCTAssertNil(KeyEquivalentText.spell(key: "", modifiers: [.command]))
  }

  /// Catches a function key that renders as its private-use character, a tofu glyph in the
  /// placeholder after an App Shortcuts remap onto an F-key.
  func testSpellsFunctionAndNavigationKeysByName() {
    let cases: [(UInt32, String)] = [
      (0xF704, "F1"), (0xF70F, "F12"), (0xF717, "F20"), (0xF726, "F35"),
      (0xF729, "\u{2196}"), (0xF72B, "\u{2198}"), (0xF72C, "\u{21DE}"),
      (0xF72D, "\u{21DF}"), (0xF728, "\u{2326}"),
    ]

    for (scalar, name) in cases {
      let key = String(UnicodeScalar(scalar)!)

      XCTAssertEqual(
        KeyEquivalentText.spell(key: key, modifiers: [.command, .shift]),
        "\u{21E7}\u{2318}" + name, name)
    }
  }

  /// Catches an unknown private-use key that renders raw. The hint is dropped instead.
  func testAnUnknownPrivateUseKeyHasNoSpelling() {
    XCTAssertNil(KeyEquivalentText.spell(key: "\u{F8FF}", modifiers: [.command]))
  }
}

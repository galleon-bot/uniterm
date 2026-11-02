import AppKit
internal import GhosttyKit
import XCTest

@testable import TerminalSurface

/// The translation from an AppKit key event to libghostty's key fields.
///
/// The expected numbers are written by hand from libghostty's header: shift 1, control 2, alt 4,
/// super 8. The key codes are the US layout's: apostrophe 39, backslash 42, space 49.
///
/// The modifiers, the consumed modifiers, and the text do not depend on the keyboard layout. The
/// unshifted codepoint does, since the layout maps the key code to a character. Those assertions
/// run only on the plain US layout and are skipped on any other, with the reason named.
@MainActor
final class KeyTranslationTests: XCTestCase {
  private let shift: UInt32 = 1
  private let control: UInt32 = 2
  private let press: UInt32 = 1

  private func event(
    keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags = []
  ) throws -> NSEvent {
    try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
        context: nil, characters: characters, charactersIgnoringModifiers: characters,
        isARepeat: false, keyCode: keyCode))
  }

  /// The unshifted codepoint is the layout's answer for the key code. Off the US layout it is not
  /// what these tests expect, so the assertion is skipped.
  private func assertUnshifted(_ actual: UInt32, _ expected: UInt32) throws {
    let layout = KeyboardLayout.id
    try XCTSkipUnless(
      layout == "com.apple.keylayout.US",
      "the unshifted codepoint depends on the layout, and this one is \(layout ?? "unknown")")

    XCTAssertEqual(actual, expected)
  }

  private func fields(
    _ event: NSEvent, text: String
  ) -> GhosttySurfaceView.KeyFields {
    GhosttySurfaceView.keyFields(
      action: GHOSTTY_ACTION_PRESS, event: event, translationEvent: event, text: text)
  }

  /// Catches a plain apostrophe that arrives with modifiers. It carries no modifier and no
  /// consumed modifier, and its text is the character.
  func testApostropheCarriesNoModifiers() throws {
    let result = fields(try event(keyCode: 39, characters: "'"), text: "'")

    XCTAssertEqual(result.action, press)
    XCTAssertEqual(result.keycode, 39)
    XCTAssertEqual(result.mods, 0)
    XCTAssertEqual(result.consumedMods, 0)
    XCTAssertEqual(result.text, "'")
    XCTAssertFalse(result.composing)
    try assertUnshifted(result.unshiftedCodepoint, 39)
  }

  /// A double quote is shift plus apostrophe. Shift is consumed by the text.
  func testDoubleQuoteIsShiftApostrophe() throws {
    let result = fields(try event(keyCode: 39, characters: "\"", modifiers: .shift), text: "\"")

    XCTAssertEqual(result.mods, shift)
    XCTAssertEqual(result.consumedMods, shift)
    XCTAssertEqual(result.text, "\"")
    try assertUnshifted(result.unshiftedCodepoint, 39)
  }

  func testPipeIsShiftBackslash() throws {
    let result = fields(try event(keyCode: 42, characters: "|", modifiers: .shift), text: "|")

    XCTAssertEqual(result.mods, shift)
    XCTAssertEqual(result.consumedMods, shift)
    XCTAssertEqual(result.text, "|")
    try assertUnshifted(result.unshiftedCodepoint, 92)
  }

  func testSpaceWithAndWithoutShift() throws {
    let plain = fields(try event(keyCode: 49, characters: " "), text: " ")
    XCTAssertEqual(plain.mods, 0)
    XCTAssertEqual(plain.consumedMods, 0)
    XCTAssertEqual(plain.text, " ")
    try assertUnshifted(plain.unshiftedCodepoint, 32)

    let shifted = fields(try event(keyCode: 49, characters: " ", modifiers: .shift), text: " ")
    XCTAssertEqual(shifted.mods, shift)
    XCTAssertEqual(shifted.consumedMods, shift)
  }

  /// Control is sent as a modifier but never consumed. This is what XCUITest delivers for an
  /// apostrophe, and the encoder then writes it as CSI 39;5u. The app passes the event's flags on
  /// faithfully, so the fault is in the synthetic event, not in the translation. See the UI test.
  func testControlIsAModifierAndNeverConsumed() throws {
    let result = fields(try event(keyCode: 39, characters: "'", modifiers: .control), text: "'")

    XCTAssertEqual(result.mods, control)
    XCTAssertEqual(result.consumedMods, 0)
    XCTAssertEqual(result.text, "'")
  }

  /// A control character in the text is dropped, since libghostty encodes control keys itself.
  func testControlCharacterTextIsDropped() throws {
    let result = fields(try event(keyCode: 36, characters: "\r"), text: "\r")

    XCTAssertNil(result.text)
  }
}

import AppKit
import AppletKit
import XCTest

@testable import TerminalApplet
@testable import WindowKit

/// The commands the terminal declares, checked against the keys uniterm reserves. A new window key
/// that lands on a terminal key fails here before it reaches a user.
@MainActor
final class TerminalCommandsTests: XCTestCase {
  /// Catches a built-in applet command that claims a reserved key or a key another of its commands
  /// holds. The menu is the app's own, built from the registry, so a window key added later joins
  /// the reserved set and fails this test. AppKit adds its keys at run time, so the full-screen key
  /// is listed here.
  func testNoTerminalCommandClaimsAReservedKeyOrAKeyOfItsOwn() {
    let registry = CommandRegistry()
    registry.register(TerminalApplet.commandSet)

    let menu = CommandMenu(registry: registry, activeController: { nil })
    var reserved = menu.reservedKeys()
    reserved.insert(KeyChord("f", [.command, .control]))

    let resolution = KeyReservations.resolve(sets: registry.appletSets, reserved: reserved)

    XCTAssertEqual(resolution.conflicts, [])

    let asked = TerminalApplet.commandSet.commands.compactMap(\.key)
    XCTAssertEqual(resolution.keys.count, asked.count)
  }

  /// Catches an ID that changed or a menu title that moved. Titles are what a user's App Shortcuts
  /// remap matches, and IDs are namespaced by the terminal.
  func testTheTerminalKeepsItsTitlesAndNamespacesItsIDs() {
    let registry = CommandRegistry()
    registry.register(TerminalApplet.commandSet)

    let expected: [String: String] = [
      "terminal.clear": "Clear Screen", "terminal.bigger-text": "Bigger Text",
      "terminal.smaller-text": "Smaller Text", "terminal.actual-size": "Actual Size",
      "terminal.new-tab": "New Tab", "terminal.next-tab": "Select Next Tab",
      "terminal.previous-tab": "Select Previous Tab", "terminal.tab-1": "Select Tab 1",
      "terminal.last-tab": "Select Last Tab",
    ]

    for (id, title) in expected {
      XCTAssertEqual(registry.command(CommandID(id))?.title, title, id)
    }

    XCTAssertEqual(
      registry.commands.filter { $0.owner == .uniterm }.count,
      registry.commands.count - TerminalApplet.commandSet.commands.count)
  }

  /// Catches Cmd-1 to Cmd-9 left reserved by uniterm. The terminal holds them, and the launcher
  /// keeps its own.
  func testTheTerminalHoldsCommandOneToNine() {
    let registry = CommandRegistry()
    registry.register(TerminalApplet.commandSet)
    let menu = CommandMenu(registry: registry, activeController: { nil })

    for number in 1...9 {
      XCTAssertFalse(menu.reservedKeys().contains(KeyChord(String(number))), "\(number)")
    }
  }
}

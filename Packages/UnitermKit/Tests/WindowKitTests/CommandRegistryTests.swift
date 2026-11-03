import AppKit
import XCTest

@testable import WindowKit

@MainActor
final class CommandRegistryTests: XCTestCase {
  /// Catches an ID that is not namespaced by its owner, which a later applet command could collide
  /// with. Duplicates trap in the registry's initializer, so building it proves there are none.
  func testEveryStandardCommandHasAnOwnedIDAndTitle() {
    let registry = CommandRegistry()

    XCTAssertGreaterThan(registry.commands.count, 20)

    for command in registry.commands {
      XCTAssertTrue(command.id.rawValue.hasPrefix("uniterm."), "\(command.id)")
      XCTAssertFalse(command.title.isEmpty)
    }
  }

  /// Catches Cmd-1 to Cmd-9 that miss a command, and number 9 that selects a ninth tab.
  func testTabNumbersMapToTheirCommands() {
    let registry = CommandRegistry()

    for number in 1...9 {
      XCTAssertNotNil(registry.command(.selectTab(number: number)), "tab \(number)")
    }

    XCTAssertEqual(CommandID.selectTab(number: 9).rawValue, "uniterm.select-last-tab")
  }

  /// Catches recency that grows without bound or keeps a command twice.
  func testRecencyKeepsEachCommandOnceAndStaysBounded() {
    let registry = CommandRegistry()

    for _ in 0..<3 {
      for id in [CommandID.newWindow, .showSettings] {
        _ = registry.runWithoutWindow(id)
      }
    }

    XCTAssertEqual(registry.recency, [.showSettings, .newWindow])
  }

  /// Catches tab-number presses that push every listed command out of the recency list.
  func testUnlistedCommandsAreNotRemembered() throws {
    let fixture = try WindowFixture()
    defer { fixture.cleanUp() }
    let controller = fixture.controller

    controller.commands.run(.splitRight, in: controller.commandContext())
    controller.commands.run(.selectTab(number: 1), in: controller.commandContext())
    controller.commands.run(.showCommandPalette, in: controller.commandContext())

    XCTAssertEqual(controller.commands.recency, [.splitRight])
  }

  /// Catches an app command that needs a window running without one, and a window command that
  /// runs with none.
  func testOnlyAppCommandsRunWithoutAWindow() {
    var opened = 0
    let registry = CommandRegistry(app: AppCommandHooks(newWindow: { opened += 1 }))

    XCTAssertTrue(registry.runWithoutWindow(.newWindow))
    XCTAssertFalse(registry.runWithoutWindow(.splitRight))
    XCTAssertEqual(opened, 1)
  }
}

/// How a typed key is matched to a menu item's key equivalent.
@MainActor
final class MenuKeyMatchTests: XCTestCase {
  private func event(_ characters: String, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
    try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
        context: nil, characters: characters, charactersIgnoringModifiers: characters,
        isARepeat: false, keyCode: 0))
  }

  private func item(_ key: String, _ flags: NSEvent.ModifierFlags) -> NSMenuItem {
    let item = NSMenuItem(title: "Item", action: nil, keyEquivalent: key)
    item.keyEquivalentModifierMask = flags
    return item
  }

  /// Catches Bigger Text missing its early route. Cmd-Shift-= types "+", and the item names Cmd
  /// alone.
  func testAShiftedSymbolMatchesAnItemThatNamesOnlyTheSymbol() throws {
    XCTAssertTrue(MenuKeyMatch.triggers(item("+", .command), try event("+", [.command, .shift])))
    XCTAssertTrue(MenuKeyMatch.triggers(item("+", .command), try event("+", .command)))
  }

  /// Catches Dismiss Message missing its early route. The Delete key sends 0x7F and the item
  /// says 0x08.
  func testDeleteMatchesTheBackspaceKeyEquivalent() throws {
    XCTAssertTrue(
      MenuKeyMatch.triggers(
        item("\u{8}", [.command, .option]), try event("\u{7F}", [.command, .option])))
  }

  /// Catches a loosened match that fires on the wrong chord: Shift still counts for letters and
  /// digits, and a different character never matches.
  func testLettersKeepTheirModifiersAndOtherCharactersDoNotMatch() throws {
    XCTAssertFalse(MenuKeyMatch.triggers(item("d", .command), try event("d", [.command, .shift])))
    XCTAssertTrue(
      MenuKeyMatch.triggers(item("d", [.command, .shift]), try event("D", [.command, .shift])))
    XCTAssertFalse(MenuKeyMatch.triggers(item("]", .command), try event("}", [.command, .shift])))
    XCTAssertTrue(
      MenuKeyMatch.triggers(item("}", [.command, .shift]), try event("}", [.command, .shift])))
    XCTAssertFalse(MenuKeyMatch.triggers(item("t", .command), try event("t", .control)))
  }
}

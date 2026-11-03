import AppletKit
import PaneModel
import XCTest

@testable import WindowKit

@MainActor
final class CloseUndoLedgerTests: XCTestCase {
  private func closed(_ number: Int) -> ClosedPane {
    ClosedPane(
      stamp: UInt64(number),
      placement: PanePlacement(
        neighbor: NodeID(rawValue: 100), axis: .row, side: .after, weight: 1),
      description: AppletDescription(type: "fake", version: 1, payload: .string("\(number)")),
      title: "Close \(number)")
  }

  /// Catches a trim that drops the newest close. With a depth of 2, the third push drops the
  /// first, and the newest stays on top.
  func testPushingPastTheDepthDropsTheOldestClose() {
    var ledger = CloseUndoLedger(policy: CloseUndoPolicy(stackDepth: 2))

    ledger.push(closed(1))
    ledger.push(closed(2))
    ledger.push(closed(3))

    XCTAssertEqual(ledger.entries.map(\.title), ["Close 2", "Close 3"])
    XCTAssertEqual(ledger.entries.last?.title, "Close 3")
  }

  /// Catches a removal that takes the newest entry when an older one was named. Removing by stamp
  /// takes only that entry, and an unknown stamp changes nothing.
  func testRemovingByStampTakesOnlyThatEntry() {
    var ledger = CloseUndoLedger(policy: .standard)

    ledger.push(closed(1))
    ledger.push(closed(2))
    ledger.push(closed(3))
    ledger.remove(stamp: 2)

    XCTAssertEqual(ledger.entries.map(\.title), ["Close 1", "Close 3"])

    ledger.remove(stamp: 99)

    XCTAssertEqual(ledger.entries.count, 2)
  }
}

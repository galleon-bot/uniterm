import AppletKit
import PaneModel
import XCTest

@testable import WindowKit

@MainActor
final class CloseUndoLedgerTests: XCTestCase {
  private func closed(_ serial: Int) -> ClosedPane {
    ClosedPane(
      paneID: NodeID(rawValue: UInt64(serial)),
      placement: PanePlacement(
        neighbor: NodeID(rawValue: 100), axis: .row, side: .after, weight: 1),
      description: AppletDescription(type: "fake", version: 1, payload: .string("\(serial)")),
      title: "Close \(serial)",
      serial: serial)
  }

  /// A pane that drops out of the hidden tier after a newer one was already described must not
  /// jump the order. It catches an undo that reopens an older close before a newer one.
  func testDescribedOrdersBySerialWhenPanesDropOutOfOrder() {
    var ledger = CloseUndoLedger(
      policy: CloseUndoPolicy(graceSlots: 3, gracePeriod: 10, stackDepth: 5))

    ledger.describe(closed(3))
    ledger.describe(closed(1))
    ledger.describe(closed(2))

    XCTAssertEqual(ledger.described.map(\.serial), [1, 2, 3])

    guard case .described(let newest)? = ledger.newest else {
      return XCTFail("expected a described entry")
    }

    XCTAssertEqual(newest.serial, 3)
  }

  /// Trimming drops the oldest close by serial, whatever order the descriptions arrived in. It
  /// catches a trim that drops the newest close because it was added first.
  func testStackTrimDropsLowestSerial() {
    var ledger = CloseUndoLedger(
      policy: CloseUndoPolicy(graceSlots: 3, gracePeriod: 10, stackDepth: 2))

    ledger.describe(closed(5))
    ledger.describe(closed(1))
    ledger.describe(closed(4))

    XCTAssertEqual(ledger.described.map(\.serial), [4, 5])
  }
}

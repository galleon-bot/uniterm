import XCTest

@testable import StatusKit

/// Each expected value below is worked out by hand from the stated rules: 1.5 s dwell, 5 s idle
/// timeout, a backlog limit of 3, and a history cap of 500. None comes from running the queue.
final class StatusQueueTests: XCTestCase {
  private let source = StatusSource.uniterm

  private func post(
    _ queue: inout StatusQueue, _ level: StatusLevel, _ text: String, at time: TimeInterval
  ) {
    queue.post(level: level, source: source, text: text, at: time)
  }

  /// Catches a first message that waits behind a dwell nobody started.
  func testFirstMessageShowsAtOnce() {
    var queue = StatusQueue()
    post(&queue, .info, "a", at: 10)

    XCTAssertEqual(queue.current?.message.text, "a")
    XCTAssertEqual(queue.pendingCount, 0)
  }

  /// Catches a message that replaces another before its minimum dwell is over.
  func testSecondMessageWaitsForTheDwell() {
    var queue = StatusQueue()
    post(&queue, .info, "a", at: 0)
    post(&queue, .info, "b", at: 1.0)

    XCTAssertEqual(queue.current?.message.text, "a")
    XCTAssertEqual(queue.nextWake(), 1.5)

    XCTAssertFalse(queue.advance(at: 1.4))
    XCTAssertEqual(queue.current?.message.text, "a")

    XCTAssertTrue(queue.advance(at: 1.5))
    XCTAssertEqual(queue.current?.message.text, "b")
  }

  /// Catches a message that arrives after the dwell and still waits for a tick.
  func testMessageAfterTheDwellReplacesAtOnce() {
    var queue = StatusQueue()
    post(&queue, .info, "a", at: 0)
    post(&queue, .info, "b", at: 2.0)

    XCTAssertEqual(queue.current?.message.text, "b")
  }

  /// A backlog of five infos at t=0 holds a, then [b c d e]. After the dwell the backlog (4) is
  /// above the limit of 3, so the bar skips to the newest, e. The skipped ones stay in history.
  func testBacklogSkipsToTheNewestAndKeepsHistory() {
    var queue = StatusQueue()
    for text in ["a", "b", "c", "d", "e"] {
      post(&queue, .info, text, at: 0)
    }

    XCTAssertEqual(queue.current?.message.text, "a")
    XCTAssertEqual(queue.pendingCount, 4)

    queue.advance(at: 1.5)

    XCTAssertEqual(queue.current?.message.text, "e")
    XCTAssertEqual(queue.pendingCount, 0)
    XCTAssertEqual(queue.history.map(\.text), ["a", "b", "c", "d", "e"])
  }

  /// A backlog at the limit is not skipped: a, then [b c d] shows b next.
  func testBacklogAtTheLimitIsNotSkipped() {
    var queue = StatusQueue()
    for text in ["a", "b", "c", "d"] {
      post(&queue, .info, text, at: 0)
    }

    queue.advance(at: 1.5)

    XCTAssertEqual(queue.current?.message.text, "b")
    XCTAssertEqual(queue.pendingCount, 2)
  }

  /// Catches a skip that drops an error. Pending after a is [b, E, c, d]. Skipping keeps E and the
  /// newest, d, so E shows first and d after it.
  func testSkippingNeverDropsAnError() {
    var queue = StatusQueue()
    post(&queue, .info, "a", at: 0)
    post(&queue, .info, "b", at: 0)
    post(&queue, .error, "E", at: 0)
    post(&queue, .info, "c", at: 0)
    post(&queue, .info, "d", at: 0)

    queue.advance(at: 1.5)
    XCTAssertEqual(queue.current?.message.text, "E")

    queue.advance(at: 3.0)
    XCTAssertEqual(queue.current?.message.text, "d")
  }

  /// Three queued errors fold into the newest with a count of two.
  func testErrorBacklogCollapsesToNewestPlusCount() {
    var queue = StatusQueue()
    post(&queue, .info, "a", at: 0)
    post(&queue, .error, "E1", at: 0)
    post(&queue, .error, "E2", at: 0)
    post(&queue, .error, "E3", at: 0)

    queue.advance(at: 1.5)

    XCTAssertEqual(queue.current?.message.text, "E3")
    XCTAssertEqual(queue.current?.collapsedErrors, 2)
    XCTAssertEqual(queue.pendingCount, 0)
  }

  /// Errors with infos between them fold too. E1 and E2 count against E3, and the infos are
  /// skipped because the backlog of six is above the limit. The bar shows E3 with a count of 2.
  func testErrorsFoldAcrossInfos() {
    var queue = StatusQueue()
    post(&queue, .info, "a", at: 0)
    post(&queue, .error, "E1", at: 0)
    post(&queue, .error, "E2", at: 0)
    post(&queue, .info, "b", at: 0)
    post(&queue, .info, "c", at: 0)
    post(&queue, .info, "d", at: 0)
    post(&queue, .error, "E3", at: 0)

    queue.advance(at: 1.5)

    XCTAssertEqual(queue.current?.message.text, "E3")
    XCTAssertEqual(queue.current?.collapsedErrors, 2)
  }

  /// An error stays past the idle timeout. It leaves only when replaced or dismissed.
  func testErrorStaysUntilReplacedOrDismissed() {
    var queue = StatusQueue()
    post(&queue, .error, "E", at: 0)

    XCTAssertFalse(queue.advance(at: 60))
    XCTAssertEqual(queue.current?.message.text, "E")
    XCTAssertNil(queue.nextWake())

    XCTAssertTrue(queue.dismissCurrent(at: 61))
    XCTAssertNil(queue.current)
  }

  /// A newer message replaces an error once the dwell is over.
  func testNewerMessageReplacesAnError() {
    var queue = StatusQueue()
    post(&queue, .error, "E", at: 0)
    post(&queue, .info, "i", at: 3)

    XCTAssertEqual(queue.current?.message.text, "i")
  }

  /// Info clears to idle 5 s after it is shown, and not before.
  func testInfoClearsAfterTheIdleTimeout() {
    var queue = StatusQueue()
    post(&queue, .info, "a", at: 100)

    XCTAssertEqual(queue.nextWake(), 105)
    XCTAssertFalse(queue.advance(at: 104.9))
    XCTAssertEqual(queue.current?.message.text, "a")

    XCTAssertTrue(queue.advance(at: 105))
    XCTAssertNil(queue.current)
  }

  /// The idle timeout waits for the queue to drain. With b pending, a is replaced at 1.5, and b
  /// then clears 5 s after it was shown, at 6.5.
  func testIdleTimeoutStartsWhenTheQueueDrains() {
    var queue = StatusQueue()
    post(&queue, .info, "a", at: 0)
    post(&queue, .info, "b", at: 0)

    queue.advance(at: 1.5)
    XCTAssertEqual(queue.current?.message.text, "b")
    XCTAssertEqual(queue.nextWake(), 6.5)

    XCTAssertTrue(queue.advance(at: 6.5))
    XCTAssertNil(queue.current)
  }

  /// Dismissing is for errors. An info message is left to its timeout.
  func testDismissLeavesInfoAlone() {
    var queue = StatusQueue()
    post(&queue, .info, "a", at: 0)

    XCTAssertFalse(queue.dismissCurrent(at: 1))
    XCTAssertEqual(queue.current?.message.text, "a")
  }

  /// Dismissing an error shows the next queued message at once.
  func testDismissShowsTheNextMessage() {
    var queue = StatusQueue()
    post(&queue, .error, "E", at: 0)
    post(&queue, .info, "i", at: 0.5)

    XCTAssertTrue(queue.dismissCurrent(at: 0.6))
    XCTAssertEqual(queue.current?.message.text, "i")
  }

  /// The unseen flag rises with an error and falls only when the history is opened.
  func testUnseenErrorFlag() {
    var queue = StatusQueue()
    XCTAssertFalse(queue.hasUnseenError)

    post(&queue, .warning, "w", at: 0)
    XCTAssertFalse(queue.hasUnseenError)

    post(&queue, .error, "E", at: 2)
    XCTAssertTrue(queue.hasUnseenError)

    queue.dismissCurrent(at: 3)
    XCTAssertTrue(queue.hasUnseenError)

    queue.markHistorySeen()
    XCTAssertFalse(queue.hasUnseenError)
  }

  /// 503 posts leave the newest 500, in order, with the 3 oldest dropped.
  func testHistoryKeepsTheNewest500() {
    var queue = StatusQueue()
    for index in 0..<503 {
      post(&queue, .info, "m\(index)", at: Double(index) * 10)
    }

    XCTAssertEqual(queue.history.count, 500)
    XCTAssertEqual(queue.history.first?.text, "m3")
    XCTAssertEqual(queue.history.last?.text, "m502")
  }

  /// The source travels with the message into the history.
  func testSourceIsRecorded() {
    var queue = StatusQueue()
    queue.post(level: .info, source: .pane(id: 7, name: "zsh"), text: "done", at: 0)

    XCTAssertEqual(queue.history.first?.source, .pane(id: 7, name: "zsh"))
    XCTAssertEqual(queue.history.first?.source.label, "zsh")
  }
}

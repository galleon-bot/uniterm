import Foundation
import XCTest

@testable import LayoutKit

@MainActor
private final class ManualScheduler {
  private(set) var pending: [(delay: TimeInterval, action: @MainActor () -> Void, id: Int)] = []
  private var next = 0
  private(set) var cancelled = 0

  func schedule(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void)
    -> @MainActor () -> Void
  {
    next += 1
    let id = next
    pending.append((delay, action, id))

    return { [self] in
      if pending.contains(where: { $0.id == id }) { cancelled += 1 }

      pending.removeAll { $0.id == id }
    }
  }

  func fire() {
    guard let last = pending.last else { return }

    pending.removeAll { $0.id == last.id }
    last.action()
  }
}

@MainActor
final class LayoutSaverTests: XCTestCase {
  private struct Boom: Error, CustomStringConvertible {
    let description: String
  }

  private func make(
    scheduler: ManualScheduler, writes: Counter, failures: Counter, fails: Bool = false
  ) -> LayoutSaver {
    LayoutSaver(
      debounce: 1, scheduler: scheduler.schedule,
      snapshot: { SavedLayout(windows: []) },
      write: { _ in
        writes.value += 1

        if fails { throw Boom(description: "disk full") }
      },
      onFailure: { _ in failures.value += 1 })
  }

  /// Catches a debounce that writes on every change. Five changes make one debounce wait, plus
  /// the one maximum wait, and one write once the debounce fires.
  func testABurstOfChangesWritesOnce() {
    let scheduler = ManualScheduler()
    let writes = Counter()
    let saver = make(scheduler: scheduler, writes: writes, failures: Counter())
    saver.enable()

    for _ in 1...5 { saver.layoutDidChange() }

    XCTAssertEqual(scheduler.pending.map(\.delay).sorted(), [1, 10])
    XCTAssertEqual(writes.value, 0)

    scheduler.fire()
    XCTAssertEqual(writes.value, 1)
    XCTAssertTrue(scheduler.pending.isEmpty, "a save drops the maximum wait too")
  }

  /// Catches debounce starvation. Changes that never stop, such as a title that animates, keep
  /// restarting the debounce, and it never fires. The maximum wait started by the first change
  /// must still write, and the next change after it starts a new wait.
  func testAnEndlessStreamOfChangesStillWritesWithinTheMaximumWait() {
    let scheduler = ManualScheduler()
    let writes = Counter()
    let saver = make(scheduler: scheduler, writes: writes, failures: Counter())
    saver.enable()

    for _ in 1...200 { saver.layoutDidChange() }

    XCTAssertEqual(writes.value, 0, "the debounce never had a quiet moment")

    let deadline = scheduler.pending.first { $0.delay == 10 }
    XCTAssertNotNil(deadline, "no maximum wait was scheduled")
    deadline?.action()

    XCTAssertEqual(writes.value, 1)
    XCTAssertTrue(scheduler.pending.isEmpty)

    saver.layoutDidChange()
    XCTAssertEqual(scheduler.pending.map(\.delay).sorted(), [1, 10])
  }

  /// Catches a quit that waits for the debounce. The change and the quit come at once, with the
  /// wait still pending. The save must happen anyway, and the pending wait must go.
  func testASaveNowCoversAPendingChange() {
    let scheduler = ManualScheduler()
    let writes = Counter()
    let saver = make(scheduler: scheduler, writes: writes, failures: Counter())
    saver.enable()

    saver.layoutDidChange()
    saver.saveNow()

    XCTAssertEqual(writes.value, 1)
    XCTAssertTrue(scheduler.pending.isEmpty)
  }

  /// Catches saves during a launch. Nothing is written until the caller enables saving.
  func testNothingIsWrittenWhileSavingIsOff() {
    let scheduler = ManualScheduler()
    let writes = Counter()
    let saver = make(scheduler: scheduler, writes: writes, failures: Counter())

    saver.layoutDidChange()
    saver.saveNow()

    XCTAssertEqual(writes.value, 0)
    XCTAssertTrue(scheduler.pending.isEmpty)

    saver.enable()
    saver.layoutDidChange()
    saver.disable()

    XCTAssertTrue(scheduler.pending.isEmpty, "disabling drops the pending save")
    saver.saveNow()
    XCTAssertEqual(writes.value, 0)
  }

  /// A write that keeps failing the same way is reported once, not once per change.
  func testARepeatedFailureIsReportedOnce() {
    let scheduler = ManualScheduler()
    let writes = Counter()
    let failures = Counter()
    let saver = make(scheduler: scheduler, writes: writes, failures: failures, fails: true)
    saver.enable()

    saver.saveNow()
    saver.saveNow()

    XCTAssertEqual(writes.value, 2)
    XCTAssertEqual(failures.value, 1)
  }
}

@MainActor
final class Counter {
  var value = 0
}

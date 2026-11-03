import AppletKit
import XCTest

final class AppletTabTests: XCTestCase {
  /// Catches an ID source that repeats a number. Every ID of one launch is distinct.
  func testIDsOfOneLaunchNeverRepeat() {
    var source = AppletTabIDSource(epoch: 7)
    let ids = (0..<1000).map { _ in source.next() }

    XCTAssertEqual(Set(ids).count, ids.count)
  }

  /// Catches an ID from an earlier launch that resolves to a tab of this one. Two launches count
  /// from one on, so their serials collide. Only the epoch tells their IDs apart.
  func testTheSameSerialInAnotherLaunchIsAnotherID() {
    var first = AppletTabIDSource(epoch: 1)
    var second = AppletTabIDSource(epoch: 2)

    let old = first.next()
    let new = second.next()

    XCTAssertEqual(old.serial, new.serial)
    XCTAssertNotEqual(old, new)
  }

  /// Catches a process that picks its epoch twice, which would let IDs repeat within a launch.
  @MainActor
  func testTheProcessIDsShareOneEpoch() {
    let ids = (0..<10).map { _ in AppletTabID.make() }

    XCTAssertEqual(Set(ids.map(\.epoch)).count, 1)
    XCTAssertEqual(Set(ids).count, 10)
  }

  /// Catches a list whose selection names a tab it does not hold, which would highlight nothing.
  @MainActor
  func testASelectionOutsideTheListFallsBackToTheFirstTab() {
    let first = AppletTab(id: .make(), title: "a")
    let second = AppletTab(id: .make(), title: "b")
    let stranger = AppletTabID.make()

    XCTAssertEqual(
      AppletTabList(first: first, rest: [second], selected: second.id).selected, second.id)
    XCTAssertEqual(
      AppletTabList(first: first, rest: [second], selected: stranger).selected, first.id)
    XCTAssertEqual(AppletTabList(first: first, rest: [second]).selected, first.id)
    XCTAssertEqual(AppletTabList(first: first, rest: [second]).all.map(\.title), ["a", "b"])
  }
}

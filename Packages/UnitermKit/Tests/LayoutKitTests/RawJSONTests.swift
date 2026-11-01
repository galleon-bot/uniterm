import Foundation
import XCTest

@testable import LayoutKit

final class RawJSONTests: XCTestCase {
  /// Catches a scanner that re-serializes a member. A saved description must come back as the
  /// same bytes, including the spacing, the key order, and a number a double cannot hold.
  func testMembersKeepTheirExactBytes() throws {
    let text = #"{ "b" :  {"z":1,  "a":[1, 2 ,3]},"a":12345678901234567890 , "s":"x\"}]y"}"#
    let members = try RawJSON(Data(text.utf8)).members()

    XCTAssertEqual(members.map(\.key), ["b", "a", "s"])
    XCTAssertEqual(
      String(decoding: members[0].value.bytes, as: UTF8.self), #"{"z":1,  "a":[1, 2 ,3]}"#)
    XCTAssertEqual(String(decoding: members[1].value.bytes, as: UTF8.self), "12345678901234567890")
    XCTAssertEqual(String(decoding: members[2].value.bytes, as: UTF8.self), #""x\"}]y""#)
  }

  /// Catches an element scanner that stops at a comma inside a nested value.
  func testElementsSplitOnlyAtTheTopLevel() throws {
    let elements = try RawJSON(Data(#"[ {"a":[1,2]}, "x,y", 3, [4,5] ]"#.utf8)).elements()

    XCTAssertEqual(
      elements.map { String(decoding: $0.bytes, as: UTF8.self) },
      [#"{"a":[1,2]}"#, #""x,y""#, "3", "[4,5]"])
  }

  func testEmptyContainers() throws {
    XCTAssertTrue(try RawJSON(Data("{ }".utf8)).members().isEmpty)
    XCTAssertTrue(try RawJSON(Data("[ ]".utf8)).elements().isEmpty)
  }

  func testTheLastRepeatedKeyWins() throws {
    let value = try RawJSON(Data(#"{"a":1,"a":2}"#.utf8)).member("a")

    XCTAssertEqual(value?.unsignedInteger, 2)
  }

  /// Catches a scanner that recurses on nesting. A hundred thousand open brackets must come back
  /// as an error or a value, never a stack overflow, and a layout of that shape is unreadable.
  func testHostileNestingNeitherCrashesNorDecodes() throws {
    let depth = 100_000
    let text = String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
    let outer = try RawJSON(Data(("[" + text + "]").utf8)).elements()

    XCTAssertEqual(outer.count, 1)
    XCTAssertThrowsError(
      try LayoutCodec.decode(Data(("{\"version\":1,\"windows\":" + text + "}").utf8)))
    XCTAssertThrowsError(
      try LayoutCodec.decode(Data(String(repeating: "{\"a\":", count: 5000).utf8)))
  }

  func testAShapeMismatchThrowsInsteadOfTrapping() {
    XCTAssertThrowsError(try RawJSON(Data("[1]".utf8)).members())
    XCTAssertThrowsError(try RawJSON(Data("{}".utf8)).elements())
    XCTAssertThrowsError(try RawJSON(Data(#"{"a":"#.utf8)).members())
    XCTAssertThrowsError(try RawJSON(Data(#"["#.utf8)).elements())
  }
}

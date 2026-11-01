import XCTest

@testable import AppletKit

final class AppletDescriptionTests: XCTestCase {
  /// Catches a payload that changes shape in a round trip. A description that uniterm cannot read
  /// is written back, so the bytes it holds must survive decode and encode.
  func testUnknownPayloadSurvivesARoundTrip() throws {
    let json = """
      {"type":"future","version":9,"payload":{"a":[1,2.5,null,true,"x"],"b":{"c":"d"}}}
      """

    let description = try JSONDecoder().decode(AppletDescription.self, from: Data(json.utf8))
    XCTAssertEqual(description.type, "future")
    XCTAssertEqual(description.version, 9)

    let again = try JSONDecoder().decode(
      AppletDescription.self, from: try JSONEncoder().encode(description))
    XCTAssertEqual(again, description)

    XCTAssertEqual(
      description.payload,
      .object([
        "a": .array([.number(1), .number(2.5), .null, .bool(true), .string("x")]),
        "b": .object(["c": .string("d")]),
      ]))
  }

  func testCodableValuesConvertBothWays() throws {
    struct Sample: Codable, Equatable {
      var name: String
      var count: Int
    }

    let value = try JSONValue(encoding: Sample(name: "n", count: 3))
    XCTAssertEqual(value, .object(["name": .string("n"), "count": .number(3)]))
    XCTAssertEqual(try value.decoded(as: Sample.self), Sample(name: "n", count: 3))
  }
}

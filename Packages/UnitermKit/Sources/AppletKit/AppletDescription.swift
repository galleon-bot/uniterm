import Foundation

/// The restorable form of an applet.
///
/// A description is inert state. Restoring an applet from it never runs a program the user did not
/// ask to run at that moment. Each applet type versions its own payload.
public struct AppletDescription: Sendable, Equatable, Codable {
  public let type: String
  public let version: Int
  public let payload: JSONValue

  /// The exact bytes the layout file held for this description, when it came from a file. A saved
  /// layout writes them back unchanged for an applet that could not be restored, so a newer build
  /// still finds what it wrote. The payload of such a description is not meaningful.
  public let verbatim: Data?

  public init(type: String, version: Int, payload: JSONValue, verbatim: Data? = nil) {
    self.type = type
    self.version = version
    self.payload = payload
    self.verbatim = verbatim
  }

  private enum CodingKeys: String, CodingKey {
    case type
    case version
    case payload
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    type = try container.decode(String.self, forKey: .type)
    version = try container.decode(Int.self, forKey: .version)
    payload = try container.decode(JSONValue.self, forKey: .payload)
    verbatim = nil
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(type, forKey: .type)
    try container.encode(version, forKey: .version)
    try container.encode(payload, forKey: .payload)
  }
}

/// Why an applet could not be restored from a description. A caller keeps the raw description and
/// shows a placeholder instead.
public enum AppletRestoreError: Error, Equatable {
  case wrongType(expected: String, found: String)
  case newerVersion(found: Int, supported: Int)
  case corrupt(String)
  case unsupported(String)
}

import Foundation

/// The restorable form of an applet.
///
/// A description is inert state. Restoring an applet from it never runs a program the user did not
/// ask to run at that moment. Each applet type versions its own payload.
public struct AppletDescription: Sendable, Equatable, Codable {
  public let type: String
  public let version: Int
  public let payload: JSONValue

  public init(type: String, version: Int, payload: JSONValue) {
    self.type = type
    self.version = version
    self.payload = payload
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

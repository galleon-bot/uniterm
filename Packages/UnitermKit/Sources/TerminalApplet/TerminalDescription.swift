import AppletKit
import Foundation

/// The restorable state of a terminal applet.
///
/// It is inert. Restoring a terminal starts a fresh shell in each tab's directory. It never runs a
/// program. A program-mode terminal will keep its command here and show it with a Run action.
public struct TerminalDescription: Codable, Equatable, Sendable {
  public enum Mode: String, Codable, Sendable {
    case shell
    case program
  }

  public struct Tab: Codable, Equatable, Sendable {
    /// The directory the shell reported last, or the directory the tab started in.
    public var workingDirectory: String?

    public init(workingDirectory: String?) {
      self.workingDirectory = workingDirectory
    }
  }

  public var mode: Mode
  public var command: String?
  public var tabs: [Tab]
  public var selectedTab: Int

  public init(mode: Mode, command: String? = nil, tabs: [Tab], selectedTab: Int = 0) {
    self.mode = mode
    self.command = command
    self.tabs = tabs
    self.selectedTab = selectedTab
  }

  public static let typeID = "terminal"

  /// The version of the payload this build reads and writes.
  public static let currentVersion = 1

  public func appletDescription() throws -> AppletDescription {
    AppletDescription(
      type: Self.typeID, version: Self.currentVersion, payload: try JSONValue(encoding: self))
  }

  /// Reads a description. A description of another type, a newer version, or a shape that does not
  /// decode is refused, and the caller keeps the original.
  public static func decode(_ description: AppletDescription) throws -> TerminalDescription {
    guard description.type == typeID else {
      throw AppletRestoreError.wrongType(expected: typeID, found: description.type)
    }

    guard description.version <= currentVersion else {
      throw AppletRestoreError.newerVersion(
        found: description.version, supported: currentVersion)
    }

    let decoded: TerminalDescription
    do {
      decoded = try description.payload.decoded(as: TerminalDescription.self)
    } catch {
      throw AppletRestoreError.corrupt("terminal description: \(error)")
    }

    guard !decoded.tabs.isEmpty else {
      throw AppletRestoreError.corrupt("terminal description has no tabs")
    }

    guard decoded.tabs.indices.contains(decoded.selectedTab) else {
      throw AppletRestoreError.corrupt("terminal description selects a missing tab")
    }

    return decoded
  }
}

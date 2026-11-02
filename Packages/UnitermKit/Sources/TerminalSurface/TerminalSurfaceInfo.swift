import Foundation
internal import GhosttyKit

/// Facts about the terminal engine. The module reaches libghostty and exposes only Swift types.
public enum TerminalSurfaceInfo {
  /// The version string of the linked libghostty.
  public static var libraryVersion: String {
    let info = ghostty_info()
    guard let version = info.version else { return "unknown" }

    let bytes = UnsafeBufferPointer(
      start: UnsafeRawPointer(version).assumingMemoryBound(to: UInt8.self),
      count: Int(info.version_len))
    return String(decoding: bytes, as: UTF8.self)
  }
}

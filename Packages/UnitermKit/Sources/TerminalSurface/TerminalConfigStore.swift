import Darwin
import Foundation

public enum TerminalConfigStoreError: Error {
  case posix(operation: String, code: Int32)
}

/// Writes the generated config to a file that belongs to one running instance.
///
/// Two instances of uniterm never share a file, so one instance's palette change cannot reach the
/// other. Each write goes to a temp file and then renames over the target. A reader sees the old
/// file or the new one, never a half-written one. The file and its directory are private to the
/// user.
public struct TerminalConfigStore: Sendable {
  public let directory: URL
  public let processID: Int32

  public init(directory: URL, processID: Int32 = ProcessInfo.processInfo.processIdentifier) {
    self.directory = directory
    self.processID = processID
  }

  /// `~/Library/Application Support/uniterm/terminal`.
  public static func defaultDirectory() throws -> URL {
    try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
    )
    .appending(path: "uniterm", directoryHint: .isDirectory)
    .appending(path: "terminal", directoryHint: .isDirectory)
  }

  public var fileURL: URL {
    directory.appending(path: Self.fileName(for: processID))
  }

  static func fileName(for processID: Int32) -> String {
    "ghostty-\(processID).conf"
  }

  /// The process ID in a config file name, or nil when the name is not one of ours.
  static func processID(fromFileName name: String) -> Int32? {
    guard name.hasPrefix("ghostty-"), name.hasSuffix(".conf") else { return nil }

    let digits = name.dropFirst("ghostty-".count).dropLast(".conf".count)
    guard !digits.isEmpty, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else {
      return nil
    }

    return Int32(digits)
  }

  @discardableResult
  public func write(_ contents: String) throws -> URL {
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])

    // createDirectory leaves an existing folder as it was. The folder must be private either way.
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

    let temp = directory.appending(
      path: ".\(Self.fileName(for: processID)).\(UUID().uuidString).tmp")
    let descriptor = open(temp.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
    guard descriptor >= 0 else {
      throw TerminalConfigStoreError.posix(operation: "open", code: errno)
    }

    do {
      try Self.writeAll(Array(contents.utf8), to: descriptor)

      guard fsync(descriptor) == 0 else {
        throw TerminalConfigStoreError.posix(operation: "fsync", code: errno)
      }
    } catch {
      close(descriptor)
      unlink(temp.path)
      throw error
    }

    close(descriptor)

    guard rename(temp.path, fileURL.path) == 0 else {
      let code = errno
      unlink(temp.path)
      throw TerminalConfigStoreError.posix(operation: "rename", code: code)
    }

    return fileURL
  }

  /// Deletes the files and the half-written temp files of instances that no longer run. Returns the
  /// files it removed.
  @discardableResult
  public func removeStaleFiles(isAlive: (Int32) -> Bool = TerminalConfigStore.processIsAlive)
    -> [URL]
  {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    var removed: [URL] = []

    for name in names {
      guard
        let owner = Self.processID(fromFileName: name) ?? Self.processID(fromTempFileName: name),
        owner != processID, !isAlive(owner)
      else { continue }

      let url = directory.appending(path: name)
      if (try? FileManager.default.removeItem(at: url)) != nil {
        removed.append(url)
      }
    }

    return removed
  }

  /// The process ID in a temp file name such as `.ghostty-77.conf.<uuid>.tmp`, or nil.
  static func processID(fromTempFileName name: String) -> Int32? {
    guard name.hasPrefix("."), name.hasSuffix(".tmp") else { return nil }

    let parts = name.dropFirst().split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4, parts[1] == "conf" else { return nil }

    return processID(fromFileName: "\(parts[0]).conf")
  }

  /// Deletes this instance's file.
  public func removeOwnFile() {
    try? FileManager.default.removeItem(at: fileURL)
  }

  public static func processIsAlive(_ processID: Int32) -> Bool {
    if kill(processID, 0) == 0 {
      return true
    }

    return errno == EPERM
  }

  private static func writeAll(_ bytes: [UInt8], to descriptor: Int32) throws {
    var offset = 0

    while offset < bytes.count {
      let written = bytes[offset...].withUnsafeBytes {
        Darwin.write(descriptor, $0.baseAddress, $0.count)
      }
      if written < 0 {
        if errno == EINTR { continue }

        throw TerminalConfigStoreError.posix(operation: "write", code: errno)
      }

      offset += written
    }
  }
}

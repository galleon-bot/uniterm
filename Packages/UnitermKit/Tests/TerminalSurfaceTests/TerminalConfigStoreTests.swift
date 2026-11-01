import Darwin
import XCTest

@testable import TerminalSurface

final class TerminalConfigStoreTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appending(
      path: "uniterm-config-\(UUID().uuidString)", directoryHint: .isDirectory)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  private func mode(of url: URL) throws -> mode_t {
    var info = stat()
    guard stat(url.path, &info) == 0 else { throw CocoaError(.fileReadNoSuchFile) }

    return info.st_mode & 0o777
  }

  private func inode(of url: URL) throws -> ino_t {
    var info = stat()
    guard stat(url.path, &info) == 0 else { throw CocoaError(.fileReadNoSuchFile) }

    return info.st_ino
  }

  /// Catches a config file that other users can read, or a directory that they can list.
  func testFileAndDirectoryArePrivate() throws {
    let store = TerminalConfigStore(directory: directory, processID: 4242)
    let file = try store.write("a = b\n")

    XCTAssertEqual(try mode(of: file), 0o600)
    XCTAssertEqual(try mode(of: directory), 0o700)
    XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "a = b\n")
  }

  /// Catches a rewrite that truncates the file in place. A reader that opened the old file keeps
  /// reading the old, complete content, and the path points at a new file.
  func testRewriteReplacesTheFileInsteadOfEditingIt() throws {
    let store = TerminalConfigStore(directory: directory, processID: 4242)
    let file = try store.write("first = 1\n")
    let oldInode = try inode(of: file)

    let reader = try FileHandle(forReadingFrom: file)
    defer { try? reader.close() }

    try store.write("second = 2\n")

    XCTAssertNotEqual(try inode(of: file), oldInode)
    XCTAssertEqual(String(decoding: try reader.readToEnd() ?? Data(), as: UTF8.self), "first = 1\n")
    XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "second = 2\n")
  }

  /// A successful write leaves no temp file behind.
  func testNoTempFilesRemainAfterAWrite() throws {
    let store = TerminalConfigStore(directory: directory, processID: 4242)
    try store.write("first = 1\n")
    try store.write("second = 2\n")

    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: directory.path), ["ghostty-4242.conf"])
  }

  /// Catches a failed write that damages the file already there. The immutable flag makes the
  /// final rename fail, after the temp file is written. The earlier file keeps its content, and the
  /// temp file is removed.
  func testFailedWriteKeepsTheOldFile() throws {
    let store = TerminalConfigStore(directory: directory, processID: 4242)
    try store.write("kept = 1\n")

    XCTAssertEqual(chflags(store.fileURL.path, UInt32(UF_IMMUTABLE)), 0)
    defer { chflags(store.fileURL.path, 0) }

    XCTAssertThrowsError(try store.write("lost = 1\n"))

    XCTAssertEqual(try String(contentsOf: store.fileURL, encoding: .utf8), "kept = 1\n")
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: directory.path), ["ghostty-4242.conf"],
      "the failed write left a temp file")
  }

  /// Catches a folder that already existed with looser permissions. The store tightens it.
  func testExistingFolderIsTightenedToPrivate() throws {
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])

    try TerminalConfigStore(directory: directory, processID: 4242).write("a = b\n")

    XCTAssertEqual(try mode(of: directory), 0o700)
  }

  /// A writer that died between creating its temp file and renaming it leaves the temp file. The
  /// cleanup removes it for a dead process and keeps it for a live one.
  func testStaleCleanupAlsoRemovesTempFilesOfDeadProcesses() throws {
    let me = TerminalConfigStore(directory: directory, processID: 300)
    try me.write("me\n")
    let dead = ".ghostty-100.conf.\(UUID().uuidString).tmp"
    let alive = ".ghostty-200.conf.\(UUID().uuidString).tmp"
    try Data("x".utf8).write(to: directory.appending(path: dead))
    try Data("x".utf8).write(to: directory.appending(path: alive))

    let removed = me.removeStaleFiles { $0 == 200 }

    XCTAssertEqual(removed.map(\.lastPathComponent), [dead])
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: directory.appending(path: alive).path))
  }

  /// Catches two instances that share a file, so one instance's palette would overwrite the other's.
  func testInstancesWriteSeparateFiles() throws {
    let first = TerminalConfigStore(directory: directory, processID: 100)
    let second = TerminalConfigStore(directory: directory, processID: 200)

    try first.write("owner = first\n")
    try second.write("owner = second\n")
    try first.write("owner = first-again\n")

    XCTAssertNotEqual(first.fileURL, second.fileURL)
    XCTAssertEqual(try String(contentsOf: first.fileURL, encoding: .utf8), "owner = first-again\n")
    XCTAssertEqual(try String(contentsOf: second.fileURL, encoding: .utf8), "owner = second\n")
  }

  /// Files of instances that no longer run are removed. A live instance's file, this instance's
  /// file, and unrelated files stay.
  func testStaleCleanupRemovesOnlyDeadInstancesFiles() throws {
    let me = TerminalConfigStore(directory: directory, processID: 300)
    try me.write("me\n")
    try TerminalConfigStore(directory: directory, processID: 100).write("dead\n")
    try TerminalConfigStore(directory: directory, processID: 200).write("alive\n")
    try Data("keep".utf8).write(to: directory.appending(path: "ghostty-abc.conf"))
    try Data("keep".utf8).write(to: directory.appending(path: "notes.txt"))

    let removed = me.removeStaleFiles { $0 == 200 }

    XCTAssertEqual(removed.map(\.lastPathComponent), ["ghostty-100.conf"])
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(),
      ["ghostty-200.conf", "ghostty-300.conf", "ghostty-abc.conf", "notes.txt"])
  }

  func testRealProcessLiveness() {
    XCTAssertTrue(TerminalConfigStore.processIsAlive(getpid()))
    XCTAssertFalse(TerminalConfigStore.processIsAlive(Int32.max - 1))
  }

  func testFileNameParsing() {
    XCTAssertEqual(TerminalConfigStore.processID(fromFileName: "ghostty-77.conf"), 77)
    XCTAssertNil(TerminalConfigStore.processID(fromFileName: "ghostty-.conf"))
    XCTAssertNil(TerminalConfigStore.processID(fromFileName: "ghostty-7x.conf"))
    XCTAssertNil(TerminalConfigStore.processID(fromFileName: ".ghostty-77.conf.tmp"))
    XCTAssertEqual(
      TerminalConfigStore.processID(fromTempFileName: ".ghostty-77.conf.AB-CD.tmp"), 77)
    XCTAssertNil(TerminalConfigStore.processID(fromTempFileName: "ghostty-77.conf"))
  }
}

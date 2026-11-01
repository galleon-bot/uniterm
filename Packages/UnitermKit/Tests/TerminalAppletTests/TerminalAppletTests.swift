import AppKit
import AppletKit
import StatusKit
import Theme
import XCTest

@testable import TerminalApplet
@testable import TerminalSurface

private final class Answers: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [Bool] = []

  func append(_ value: Bool) {
    lock.lock()
    values.append(value)
    lock.unlock()
  }

  var all: [Bool] {
    lock.lock()
    defer { lock.unlock() }
    return values
  }
}

@MainActor
private final class FakeSession: TerminalSession {
  let view = NSView()
  var onEvent: (@MainActor (TerminalEvent) -> Void)?
  var title = ""
  var workingDirectory: String?
  var gridSize = TerminalGridSize(columns: 80, rows: 24)
  var isRunningSomething = false
  var hasExited = false
  var closed = false
  var visible = true
  var launch: TerminalLaunch

  init(launch: TerminalLaunch) { self.launch = launch }

  func send(text: String) {}
  func perform(_ action: TerminalAction) {}
  func resize(to size: CGSize) {}
  func setFocused(_ focused: Bool) {}
  func setVisible(_ visible: Bool) { self.visible = visible }
  func close() { closed = true }
}

@MainActor
private final class FakeEngine: TerminalEngine {
  var sessions: [FakeSession] = []
  var anySessionRunningSomething = false

  func makeSession(launch: TerminalLaunch) throws -> any TerminalSession {
    let session = FakeSession(launch: launch)
    sessions.append(session)
    return session
  }

  func apply(palette: ThemePalette) throws {}
}

@MainActor
private final class RecordingHost: AppletHost {
  var posts: [(StatusLevel, String)] = []
  var exited = false
  var changed = 0
  var confirmations: [AppletConfirmation] = []
  var answer = false

  func applet(_ applet: any Applet, post level: StatusLevel, text: String) {
    posts.append((level, text))
  }

  func appletDidExit(_ applet: any Applet) { exited = true }
  func appletDidChange(_ applet: any Applet) { changed += 1 }

  func applet(_ applet: any Applet, confirm request: AppletConfirmation) async -> Bool {
    confirmations.append(request)
    return answer
  }
}

@MainActor
final class TerminalAppletTests: XCTestCase {
  /// A session holds its applet weakly, so a test that drops the applet would drop the handler.
  private var retained: [TerminalApplet] = []

  private func makeApplet() -> (TerminalApplet, FakeEngine, RecordingHost, FakeSession) {
    let engine = FakeEngine()
    let host = RecordingHost()
    let applet = TerminalApplet(engine: engine)
    applet.host = host
    applet.start()
    retained.append(applet)
    return (applet, engine, host, engine.sessions[0])
  }

  /// Waits for the applet's confirmation task, which hops through the main actor.
  private func settle(_ condition: () -> Bool) async {
    for _ in 0..<200 where !condition() {
      try? await Task.sleep(for: .milliseconds(10))
    }
  }

  /// Catches an applet that starts a shell by reaching past the protocol, or that never hosts the
  /// session's view.
  func testStartMakesOneSessionAndHostsItsView() {
    let (applet, engine, _, session) = makeApplet()

    XCTAssertEqual(engine.sessions.count, 1)
    XCTAssertTrue(session.view.superview === applet.view)
  }

  /// Catches a pane that stays open after its shell ends.
  func testExitAsksTheHostToClosePane() {
    let (_, _, host, session) = makeApplet()

    session.onEvent?(.exited)

    XCTAssertTrue(host.exited)
  }

  /// Catches a notification that posts without a source level, or one whose control characters
  /// forge a second line in the status bar.
  func testNotificationPostsSanitizedInfo() {
    let (_, _, host, session) = makeApplet()

    session.onEvent?(.notification(title: "Build\nOK", body: "all\u{1B}[31m done"))

    XCTAssertEqual(host.posts.count, 1)
    XCTAssertEqual(host.posts[0].0, .info)
    XCTAssertFalse(host.posts[0].1.contains("\n"))
    XCTAssertFalse(host.posts[0].1.contains("\u{1B}"))
    XCTAssertEqual(host.posts[0].1, "Build OK: all [31m done")
  }

  func testLongNotificationIsCapped() {
    let (_, _, host, session) = makeApplet()

    session.onEvent?(.notification(title: "", body: String(repeating: "x", count: 5000)))

    XCTAssertEqual(host.posts[0].1.count, 200)
  }

  /// Catches an OSC 52 read that is answered before the user chose. The request is open while the
  /// host's answer is pending, and a declined request stays declined.
  func testClipboardReadWaitsForTheUserAndDenies() async {
    let (_, _, host, session) = makeApplet()
    host.answer = false

    let answers = Answers()
    let request = TerminalClipboardRequest(kind: .read, text: "secret") { answers.append($0) }
    session.onEvent?(.clipboardRequest(request))

    XCTAssertEqual(answers.all, [], "answered before the host was asked")

    await settle { answers.all.count == 1 }

    XCTAssertEqual(host.confirmations.count, 1)
    XCTAssertEqual(answers.all, [false])
    XCTAssertTrue(host.confirmations[0].detail.contains("secret"))
  }

  func testClipboardReadIsAllowedOnlyWhenTheUserAgrees() async {
    let (_, _, host, session) = makeApplet()
    host.answer = true

    let answers = Answers()
    let request = TerminalClipboardRequest(kind: .read, text: "x") { answers.append($0) }
    session.onEvent?(.clipboardRequest(request))

    await settle { answers.all.count == 1 }

    XCTAssertEqual(answers.all, [true])
  }

  /// A second answer to one request does nothing.
  func testRequestResolvesOnce() {
    let answers = Answers()
    let request = TerminalClipboardRequest(kind: .write, text: "x") { answers.append($0) }

    request.resolve(allow: true)
    request.resolve(allow: false)

    XCTAssertEqual(answers.all, [true])
  }

  func testDetachHidesAndReattachShowsTheSameSession() {
    let (applet, engine, _, session) = makeApplet()

    applet.detach()
    XCTAssertFalse(session.visible)

    applet.reattach()
    XCTAssertTrue(session.visible)
    XCTAssertEqual(engine.sessions.count, 1)
  }

  func testRunningStateComesFromTheSession() {
    let (applet, _, _, session) = makeApplet()

    XCTAssertFalse(applet.isRunningSomething)
    session.isRunningSomething = true
    XCTAssertTrue(applet.isRunningSomething)

    session.hasExited = true
    XCTAssertFalse(applet.isRunningSomething)
  }

  func testCloseHangsUpTheSession() {
    let (applet, _, _, session) = makeApplet()

    applet.close()

    XCTAssertTrue(session.closed)
    XCTAssertTrue(applet.view.subviews.isEmpty)
  }

  /// The description follows the shell's last reported directory, and restoring it starts a shell
  /// in that directory. Nothing else runs.
  func testDescriptionTracksDirectoryAndRestores() throws {
    let (applet, engine, _, session) = makeApplet()
    session.onEvent?(.workingDirectoryChanged("/var/tmp"))

    let description = applet.describe()
    let restored = try TerminalApplet(engine: engine, restoring: description)
    restored.start()

    XCTAssertEqual(engine.sessions.count, 2)
    XCTAssertEqual(engine.sessions[1].launch.workingDirectory, "/var/tmp")
  }

  /// Catches segments that go stale, or a change that does not tell the host.
  func testSegmentsFollowTheDirectoryAndTheLastExitCode() {
    let (applet, _, host, session) = makeApplet()
    XCTAssertEqual(applet.segments, [])

    session.onEvent?(.workingDirectoryChanged("/var/tmp"))
    XCTAssertEqual(applet.segments, [AppletSegment(symbolName: "folder", text: "tmp")])
    XCTAssertEqual(host.changed, 1)

    session.onEvent?(.commandFinished(exitCode: 2, duration: .seconds(1)))
    XCTAssertEqual(
      applet.segments,
      [
        AppletSegment(symbolName: "folder", text: "tmp"),
        AppletSegment(symbolName: "xmark.circle", text: "2", style: .error),
      ])
    XCTAssertEqual(host.changed, 2)

    session.onEvent?(.commandFinished(exitCode: 0, duration: .seconds(1)))
    XCTAssertEqual(applet.segments, [AppletSegment(symbolName: "folder", text: "tmp")])
    XCTAssertEqual(host.changed, 3)
  }

  /// Catches a directory label that shows a long path, or the home folder as its own name.
  func testDirectoryLabelShowsTheLastComponentAndTildeForHome() {
    XCTAssertEqual(TerminalApplet.directoryLabel("/Users/pat", home: "/Users/pat"), "~")
    XCTAssertEqual(TerminalApplet.directoryLabel("/Users/pat/src/app", home: "/Users/pat"), "app")
    XCTAssertEqual(TerminalApplet.directoryLabel("/", home: "/Users/pat"), "/")
    XCTAssertEqual(TerminalApplet.directoryLabel("/tmp/a\nb", home: "/Users/pat"), "a b")
  }

  /// ADR: a description never runs a program unasked. A program-mode description is refused until
  /// program mode can show its command with a Run action.
  func testProgramDescriptionDoesNotRestoreIntoARunningProgram() throws {
    let engine = FakeEngine()
    let description = try TerminalDescription(
      mode: .program, command: "./deploy.sh", tabs: [.init(workingDirectory: nil)]
    ).appletDescription()

    XCTAssertThrowsError(try TerminalApplet(engine: engine, restoring: description))
    XCTAssertTrue(engine.sessions.isEmpty)
  }
}

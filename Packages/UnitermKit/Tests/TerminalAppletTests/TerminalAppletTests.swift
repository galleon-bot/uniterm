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
    let request = TerminalClipboardRequest(kind: .read, text: "x") { answers.append($0) }

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
    XCTAssertNil(session.view.superview)
  }

  /// The description follows the shell's last reported directory, and restoring it starts a shell
  /// in that directory. Nothing else runs.
  func testDescriptionTracksDirectoryAndRestores() throws {
    let (applet, engine, _, session) = makeApplet()
    session.onEvent?(.workingDirectoryChanged("/var/tmp"))

    let description = applet.describe()
    let restored = try TerminalApplet(
      engine: engine, restoring: description, directoryExists: { _ in true })
    retained.append(restored)
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

  private func programDescription(
    _ command: String? = "./deploy.sh --now", directory: String? = "/work"
  ) throws -> AppletDescription {
    try TerminalDescription(
      mode: .program, command: command, tabs: [.init(workingDirectory: directory)]
    ).appletDescription()
  }

  private func restoreProgram(
    _ description: AppletDescription, engine: FakeEngine, host: RecordingHost
  ) throws -> TerminalApplet {
    let restored = try TerminalApplet(
      engine: engine, restoring: description, directoryExists: { _ in true })
    restored.host = host
    retained.append(restored)
    restored.start()
    return restored
  }

  /// Catches a restore that runs the program unasked. Starting a restored program-mode applet makes
  /// no session, shows the command with a Run button, and asks the host nothing. The applet is not
  /// running anything, so closing it never needs a dialog.
  func testProgramDescriptionRestoresIntoAPromptThatRunsNothing() throws {
    let engine = FakeEngine()
    let host = RecordingHost()

    let restored = try restoreProgram(try programDescription(), engine: engine, host: host)

    XCTAssertTrue(engine.sessions.isEmpty, "a session started without the user asking")
    XCTAssertFalse(host.exited, "an applet waiting to run asked its pane to close")
    XCTAssertFalse(restored.isRunningSomething)
    XCTAssertTrue(restored.isAwaitingRun)

    let prompt = try XCTUnwrap(
      restored.view.subviews.compactMap { $0 as? TerminalRunPrompt }.first)
    XCTAssertFalse(prompt.isHidden)
    XCTAssertEqual(prompt.command, "./deploy.sh --now")
  }

  /// Catches a Run action that does not start the one program. Pressing Run makes exactly one
  /// session. It runs the saved words in the saved directory, in program mode, and hides the prompt.
  func testRunStartsTheSavedProgramOnce() throws {
    let engine = FakeEngine()
    let host = RecordingHost()
    let restored = try restoreProgram(try programDescription(), engine: engine, host: host)
    let prompt = try XCTUnwrap(
      restored.view.subviews.compactMap { $0 as? TerminalRunPrompt }.first)

    prompt.run()
    prompt.run()

    XCTAssertEqual(engine.sessions.count, 1)
    XCTAssertEqual(engine.sessions[0].launch.program, ["./deploy.sh", "--now"])
    XCTAssertEqual(engine.sessions[0].launch.workingDirectory, "/work")
    XCTAssertTrue(prompt.isHidden)
    XCTAssertFalse(restored.isAwaitingRun)
    XCTAssertFalse(restored.canOpenTab)
  }

  /// Catches a description that forgets the command after a restore, so a second close and undo
  /// would lose it.
  func testARestoredProgramDescribesItselfWithTheSameCommand() throws {
    let host = RecordingHost()
    let restored = try restoreProgram(try programDescription(), engine: FakeEngine(), host: host)

    let again = try TerminalDescription.decode(restored.describe())

    XCTAssertEqual(again.mode, .program)
    XCTAssertEqual(again.command, "./deploy.sh --now")
  }

  /// Catches a stored command that cannot be read and still restores. An unclosed quote and a
  /// missing command are corrupt, and no session starts.
  func testAProgramDescriptionWithoutAUsableCommandIsRefused() throws {
    let engine = FakeEngine()

    for command in ["echo 'open", nil] {
      let description = try programDescription(command)

      XCTAssertThrowsError(try TerminalApplet(engine: engine, restoring: description)) { error in
        guard case .corrupt = error as? AppletRestoreError else {
          return XCTFail("expected a corrupt description, got \(error)")
        }
      }
    }

    XCTAssertTrue(engine.sessions.isEmpty)
  }

  /// Catches a restored shell that starts in a directory the description cannot vouch for. Each
  /// tab's reported directory wins when it exists. Otherwise its starting directory is next, and
  /// the home directory is last. A path that is not absolute, such as one from a remote login, is
  /// skipped even when something by that name exists.
  func testRestoredShellsFollowTheDirectoryRule() throws {
    let engine = FakeEngine()
    let description = try TerminalDescription(
      mode: .shell, command: nil,
      tabs: [
        .init(workingDirectory: "/reported", startDirectory: "/start"),
        .init(workingDirectory: "/gone", startDirectory: "/start"),
        .init(workingDirectory: "/gone", startDirectory: "/also-gone"),
        .init(workingDirectory: "me@host:/srv", startDirectory: nil),
      ]
    ).appletDescription()

    let existing: Set<String> = ["/reported", "/start", "me@host:/srv"]
    let restored = try TerminalApplet(
      engine: engine, restoring: description, directoryExists: { existing.contains($0) },
      home: "/home/pat")
    retained.append(restored)
    restored.start()

    XCTAssertEqual(
      engine.sessions.map { $0.launch.workingDirectory },
      ["/reported", "/start", "/home/pat", "/home/pat"])
    XCTAssertTrue(engine.sessions.allSatisfy { $0.launch.program == nil })
  }

  /// Catches a description that drops the starting directory, so the fallback has nothing to use.
  /// A tab launched in /start that has since reported /elsewhere describes both.
  func testTheDescriptionCarriesTheStartingDirectory() throws {
    let engine = FakeEngine()
    let applet = TerminalApplet(engine: engine, launch: .loginShell(workingDirectory: "/start"))
    retained.append(applet)
    applet.start()
    engine.sessions[0].onEvent?(.workingDirectoryChanged("/elsewhere"))

    let described = try TerminalDescription.decode(applet.describe())

    XCTAssertEqual(described.tabs[0].workingDirectory, "/elsewhere")
    XCTAssertEqual(described.tabs[0].startDirectory, "/start")
  }

  /// Catches a description from before the starting directory existed that no longer reads.
  func testADescriptionWithoutAStartingDirectoryStillReads() throws {
    let payload: JSONValue = .object([
      "mode": .string("shell"), "selectedTab": .number(0),
      "tabs": .array([.object(["workingDirectory": .string("/old")])]),
    ])

    let decoded = try TerminalDescription.decode(
      AppletDescription(type: "terminal", version: 1, payload: payload))

    XCTAssertEqual(decoded.tabs[0].workingDirectory, "/old")
    XCTAssertNil(decoded.tabs[0].startDirectory)
  }

  // MARK: Tabs

  private func tabBar(of applet: TerminalApplet) throws -> TerminalTabBar {
    try XCTUnwrap(applet.view.subviews.compactMap { $0 as? TerminalTabBar }.first)
  }

  /// Catches a tab bar that shows for a single tab, or that stays after the second tab closes.
  func testTheTabBarShowsOnlyWhileThereIsMoreThanOneTab() async throws {
    let (applet, _, _, _) = makeApplet()
    let bar = try tabBar(of: applet)
    XCTAssertTrue(bar.isHidden)

    applet.openTab()
    XCTAssertFalse(bar.isHidden)

    let closed = await applet.closeSelectedTab()
    XCTAssertTrue(closed)
    XCTAssertTrue(bar.isHidden)
  }

  /// Catches a new tab that reuses the first tab's session, so both would share one tty. Each tab
  /// gets its own session, and only the selected one is shown and visible.
  func testEachTabIsItsOwnSessionAndOnlyTheSelectedOneShows() {
    let (applet, engine, _, _) = makeApplet()

    applet.openTab()

    XCTAssertEqual(engine.sessions.count, 2)
    XCTAssertFalse(engine.sessions[0] === engine.sessions[1])
    XCTAssertTrue(engine.sessions[0].view.isHidden)
    XCTAssertFalse(engine.sessions[1].view.isHidden)
    XCTAssertFalse(engine.sessions[0].visible)
    XCTAssertTrue(engine.sessions[1].visible)
    XCTAssertEqual(applet.tabCount, 2)
    XCTAssertEqual(applet.selectedTabIndex, 1)

    applet.selectTab(at: 0)

    XCTAssertFalse(engine.sessions[0].view.isHidden)
    XCTAssertTrue(engine.sessions[1].view.isHidden)
    XCTAssertTrue(engine.sessions[0].visible)
    XCTAssertFalse(engine.sessions[1].visible)
  }

  /// Catches a terminal that draws under the tab bar. The bar is 28 points. A 300 point applet gives
  /// 272 to the terminal while there are two tabs and all 300 with one.
  func testTheTerminalFillsWhatTheBarLeaves() async throws {
    let (applet, engine, _, _) = makeApplet()
    applet.view.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
    XCTAssertEqual(engine.sessions[0].view.frame, NSRect(x: 0, y: 0, width: 400, height: 300))

    applet.openTab()
    XCTAssertEqual(engine.sessions[1].view.frame, NSRect(x: 0, y: 28, width: 400, height: 272))

    applet.view.frame = NSRect(x: 0, y: 0, width: 500, height: 200)
    XCTAssertEqual(engine.sessions[1].view.frame, NSRect(x: 0, y: 28, width: 500, height: 172))

    let closed = await applet.closeSelectedTab()
    XCTAssertTrue(closed)
    XCTAssertEqual(engine.sessions[0].view.frame, NSRect(x: 0, y: 0, width: 500, height: 200))
  }

  /// Catches a new tab that starts elsewhere than the tab it was opened from, or lands at the end.
  /// With tabs in /a and /b and the first selected, the new tab starts in /a and sits between them.
  func testANewTabStartsInTheSelectedTabsDirectoryAndSitsRightAfterIt() throws {
    let (applet, engine, _, first) = makeApplet()
    first.onEvent?(.workingDirectoryChanged("/a"))
    applet.openTab()
    engine.sessions[1].onEvent?(.workingDirectoryChanged("/b"))
    applet.selectTab(at: 0)

    applet.openTab()

    XCTAssertEqual(engine.sessions[2].launch.workingDirectory, "/a")
    XCTAssertNil(engine.sessions[2].launch.program)
    engine.sessions[2].onEvent?(.workingDirectoryChanged("/c"))

    let description = try TerminalDescription.decode(applet.describe())
    XCTAssertEqual(description.tabs.map(\.workingDirectory), ["/a", "/c", "/b"])
    XCTAssertEqual(description.selectedTab, 1)
  }

  /// Catches program mode that opens a second tab. The one tab is the one program.
  func testProgramModeRunsOneProgramAndOpensNoTab() throws {
    let engine = FakeEngine()
    let applet = try TerminalApplet(engine: engine, program: "vim -u NONE -N 'my file'")
    retained.append(applet)
    applet.start()

    XCTAssertFalse(applet.canOpenTab)
    applet.openTab()

    XCTAssertEqual(engine.sessions.count, 1)
    XCTAssertEqual(applet.tabCount, 1)
    XCTAssertEqual(engine.sessions[0].launch.program, ["vim", "-u", "NONE", "-N", "my file"])
    XCTAssertTrue(engine.sessions[0].launch.environment.isEmpty)
    XCTAssertEqual(applet.title, "vim")
  }

  /// Catches a description that loses the program or the mode. It stays data: building the applet
  /// and describing it starts nothing beyond the one session the caller asked for.
  func testProgramDescriptionKeepsTheModeAndTheCommand() throws {
    let engine = FakeEngine()
    let applet = try TerminalApplet(engine: engine, program: "./deploy.sh --dry-run")

    let description = try TerminalDescription.decode(applet.describe())

    XCTAssertEqual(description.mode, .program)
    XCTAssertEqual(description.command, "./deploy.sh --dry-run")
    XCTAssertEqual(description.tabs.count, 1)
    XCTAssertTrue(engine.sessions.isEmpty)
  }

  /// Catches a command line that reaches a shell. Each of these would run something other than one
  /// program, or nothing at all, so the applet refuses it before any session starts.
  func testProgramLinesThatAreNotOneProgramAreRefusedBeforeAnythingStarts() {
    let engine = FakeEngine()
    let lines = ["", "   ", "ls | less", "echo 'oops", "rm -rf ~", "echo $HOME", "a; b", "x \\"]

    for line in lines {
      XCTAssertThrowsError(try TerminalApplet(engine: engine, program: line), "\(line)") {
        XCTAssertTrue($0 is ShellWordsError, "\(line) threw \($0)")
      }
    }

    XCTAssertTrue(engine.sessions.isEmpty)
  }

  /// Catches `program:` that builds its launch some way other than the program launch, which would
  /// drop the ssh fallback TERM. The rule itself is owned by the ShellWords and integration tests.
  func testProgramModeSshGetsAFallbackTerm() throws {
    let engine = FakeEngine()

    for (line, expected) in [
      ("ssh -F /dev/null host", "xterm-256color"),
      ("/usr/bin/ssh host", "xterm-256color"),
      ("ssh-keygen -l", nil),
      ("mosh host", nil),
    ] as [(String, String?)] {
      let applet = try TerminalApplet(engine: engine, program: line)
      retained.append(applet)
      applet.start()

      XCTAssertEqual(engine.sessions.last?.launch.environment["TERM"], expected, line)
    }
  }

  /// Catches a tab close that ends a program without asking. An idle tab closes at once. A tab
  /// running something asks, naming the tab by its title, and stays open when the user declines.
  func testClosingATabRunningSomethingAsksAndAnIdleTabDoesNot() async {
    let (applet, engine, host, _) = makeApplet()
    applet.openTab()
    engine.sessions[1].onEvent?(.titleChanged("vim notes.txt"))

    let idleClosed = await applet.closeSelectedTab()
    XCTAssertTrue(idleClosed)
    XCTAssertTrue(host.confirmations.isEmpty, "an idle prompt asked first")
    XCTAssertTrue(engine.sessions[1].closed)
    XCTAssertEqual(applet.tabCount, 1)

    applet.openTab()
    engine.sessions[2].onEvent?(.titleChanged("vim notes.txt"))
    engine.sessions[2].isRunningSomething = true
    host.answer = false

    let declined = await applet.closeSelectedTab()
    XCTAssertFalse(declined)
    XCTAssertEqual(host.confirmations.count, 1)
    XCTAssertTrue(
      host.confirmations.first?.detail.contains("\u{201C}vim notes.txt\u{201D}") ?? false)
    XCTAssertEqual(applet.tabCount, 2)
    XCTAssertFalse(engine.sessions[2].closed)

    host.answer = true
    let accepted = await applet.closeSelectedTab()
    XCTAssertTrue(accepted)
    XCTAssertEqual(host.confirmations.count, 2)
    XCTAssertEqual(applet.tabCount, 1)
    XCTAssertTrue(engine.sessions[2].closed)
  }

  /// Catches the last tab closing as a tab. It is a pane close, which the host owns, so the applet
  /// refuses and leaves its session running, whatever that session is doing.
  func testTheLastTabIsNeverClosedAsATab() async {
    let (applet, _, host, session) = makeApplet()
    session.isRunningSomething = true

    let closed = await applet.closeSelectedTab()

    XCTAssertFalse(closed)
    XCTAssertTrue(host.confirmations.isEmpty)
    XCTAssertFalse(session.closed)
    XCTAssertEqual(applet.tabCount, 1)
  }

  /// Catches a pane that reads as idle while a background tab runs something, which would let a
  /// later close skip its dialog. The pane is running when any tab is, and the labels name them.
  func testAPaneIsRunningSomethingWhenAnyTabIs() {
    let (applet, engine, _, first) = makeApplet()
    first.onEvent?(.titleChanged("vim"))
    applet.openTab()
    XCTAssertFalse(applet.isRunningSomething)

    first.isRunningSomething = true

    XCTAssertEqual(applet.selectedTabIndex, 1)
    XCTAssertTrue(applet.isRunningSomething)
    XCTAssertEqual(applet.runningTabLabels, ["vim"])

    first.isRunningSomething = false
    engine.sessions[1].isRunningSomething = true
    engine.sessions[1].hasExited = true
    XCTAssertFalse(applet.isRunningSomething, "an exited tab still counts")
  }

  /// Catches status bar segments that follow the last event instead of the selected tab. Tab one
  /// is in /var/tmp with a failed command. Tab two starts in the same directory with no failure. A
  /// background tab's new directory still reaches the host, which saves the layout. It does not
  /// change the segments.
  func testSegmentsReflectTheSelectedTab() {
    let (applet, engine, host, first) = makeApplet()
    first.onEvent?(.workingDirectoryChanged("/var/tmp"))
    first.onEvent?(.commandFinished(exitCode: 2, duration: .seconds(1)))

    applet.openTab()
    XCTAssertEqual(applet.segments, [AppletSegment(symbolName: "folder", text: "tmp")])

    engine.sessions[1].onEvent?(.workingDirectoryChanged("/Users/x/proj"))
    XCTAssertEqual(applet.segments, [AppletSegment(symbolName: "folder", text: "proj")])

    let changes = host.changed
    first.onEvent?(.workingDirectoryChanged("/etc"))
    XCTAssertEqual(applet.segments, [AppletSegment(symbolName: "folder", text: "proj")])
    XCTAssertGreaterThan(host.changed, changes, "a background directory change was never saved")

    applet.selectTab(at: 0)
    XCTAssertEqual(
      applet.segments,
      [
        AppletSegment(symbolName: "folder", text: "etc"),
        AppletSegment(symbolName: "xmark.circle", text: "2", style: .error),
      ])
    XCTAssertGreaterThan(host.changed, changes)
  }

  /// Catches a pane that closes when one of several shells exits, or stays open when the last one
  /// does.
  func testAShellExitClosesItsTabAndOnlyTheLastClosesThePane() {
    let (applet, engine, host, first) = makeApplet()
    applet.openTab()
    applet.selectTab(at: 0)

    engine.sessions[1].hasExited = true
    engine.sessions[1].onEvent?(.exited)

    XCTAssertFalse(host.exited)
    XCTAssertEqual(applet.tabCount, 1)
    XCTAssertTrue(engine.sessions[1].closed)

    first.hasExited = true
    first.onEvent?(.exited)

    XCTAssertTrue(host.exited)
  }

  /// Catches a pane close that leaves a background tab's shell running.
  func testClosingTheAppletClosesEveryTab() {
    let (applet, engine, _, _) = makeApplet()
    applet.openTab()
    applet.openTab()

    applet.close()

    XCTAssertEqual(engine.sessions.count, 3)
    XCTAssertTrue(engine.sessions.allSatisfy { $0.closed })
  }

  /// Catches a description that drops tabs or the selection. Restoring starts a fresh shell in each
  /// tab's directory, runs no program, and selects the same tab.
  func testDescriptionKeepsEveryTabAndRestoresThem() throws {
    let (applet, engine, _, first) = makeApplet()
    first.onEvent?(.workingDirectoryChanged("/one"))
    applet.openTab()
    engine.sessions[1].onEvent?(.workingDirectoryChanged("/two"))
    applet.openTab()
    engine.sessions[2].onEvent?(.workingDirectoryChanged("/three"))
    applet.selectTab(at: 1)

    let description = applet.describe()
    let restored = try TerminalApplet(
      engine: engine, restoring: description, directoryExists: { _ in true })
    retained.append(restored)
    restored.start()

    XCTAssertEqual(engine.sessions.count, 6)
    XCTAssertEqual(
      engine.sessions[3...].map { $0.launch.workingDirectory }, ["/one", "/two", "/three"])
    XCTAssertTrue(engine.sessions[3...].allSatisfy { $0.launch.program == nil })
    XCTAssertEqual(restored.tabCount, 3)
    XCTAssertEqual(restored.selectedTabIndex, 1)
  }
}

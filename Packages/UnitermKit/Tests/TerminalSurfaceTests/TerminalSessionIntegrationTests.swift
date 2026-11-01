import AppKit
import Theme
import XCTest

@testable import TerminalSurface

/// Runs a real zsh through the session protocol, inside a window that is never shown.
///
/// These tests start real shells, so each costs about a second. A mock cannot prove what they
/// prove: that libghostty injects shell integration, that the integration's OSC 7 and OSC 133
/// reach the protocol, and that the running-state query follows the prompt.
@MainActor
final class TerminalSessionIntegrationTests: XCTestCase {
  private var sandbox: URL!
  private var engine: GhosttyTerminalEngine!
  private var window: NSWindow!
  private var sessions: [any TerminalSession] = []
  private var savedEnvironment: [String: String?] = [:]

  override func setUp() async throws {
    continueAfterFailure = false
    _ = NSApplication.shared

    sandbox = FileManager.default.temporaryDirectory.appending(
      path: "uniterm-session-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: sandbox.appending(path: "home"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: sandbox.appending(path: "work"), withIntermediateDirectories: true)
    try Data().write(to: sandbox.appending(path: "home/.zshrc"))

    let resources = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appending(path: "Frameworks/GhosttyResources/ghostty")
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: resources.appending(path: "shell-integration").path),
      "run `make build` so Ghostty's resources exist")

    // The shell must not read the developer's dotfiles, which may prompt for an ssh passphrase.
    // ZDOTDIR goes in the process environment, since Ghostty's zsh integration reads it there and
    // restores it for the user's startup files. A ZDOTDIR passed as a launch variable would
    // override the integration's own.
    for name in ["SHELL", "ZDOTDIR", "SSH_AUTH_SOCK", "SSH_ASKPASS"] {
      savedEnvironment[name] = getenv(name).map { String(cString: $0) }
    }

    setenv("SHELL", "/bin/zsh", 1)
    setenv("ZDOTDIR", sandbox.appending(path: "home").path, 1)
    setenv("SSH_AUTH_SOCK", "", 1)
    unsetenv("SSH_ASKPASS")
    engine = try GhosttyTerminalEngine(
      configStore: TerminalConfigStore(directory: sandbox.appending(path: "config")),
      resourcesDirectory: resources, palette: .latte)

    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 400), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
  }

  override func tearDown() async throws {
    for session in sessions {
      session.close()
    }
    sessions = []
    engine = nil
    window.close()
    try? FileManager.default.removeItem(at: sandbox)

    for (name, value) in savedEnvironment {
      if let value {
        setenv(name, value, 1)
      } else {
        unsetenv(name)
      }
    }
    savedEnvironment = [:]
  }

  private func startShell() throws -> any TerminalSession {
    let launch = TerminalLaunch.loginShell(
      workingDirectory: sandbox.appending(path: "work").path,
      environment: ["HOME": sandbox.appending(path: "home").path])
    let session = try engine.makeSession(launch: launch)
    sessions.append(session)

    session.view.frame = window.contentView!.bounds
    window.contentView!.addSubview(session.view)
    session.setFocused(true)
    return session
  }

  private func waitUntil(
    _ description: String, timeout: Duration = .seconds(20), _ condition: () -> Bool
  ) async throws {
    let deadline = ContinuousClock.now + timeout

    while !condition() {
      if ContinuousClock.now > deadline {
        XCTFail("timed out waiting for \(description). Screen:\n\(sessions.last.map(screen) ?? "")")
        throw CancellationError()
      }

      try await Task.sleep(for: .milliseconds(25))
    }
  }

  /// `send(text:)` pastes, and a shell does not run a pasted newline. Enter is a real key event.
  private func press(
    _ session: any TerminalSession, keyCode: UInt16, characters: String,
    modifiers: NSEvent.ModifierFlags = []
  ) throws {
    for type in [NSEvent.EventType.keyDown, .keyUp] {
      let event = try XCTUnwrap(
        NSEvent.keyEvent(
          with: type, location: .zero, modifierFlags: modifiers, timestamp: 0,
          windowNumber: window.windowNumber, context: nil, characters: characters,
          charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))

      if type == .keyDown {
        session.view.keyDown(with: event)
      } else {
        session.view.keyUp(with: event)
      }
    }
  }

  private func run(_ command: String, in session: any TerminalSession) throws {
    session.send(text: command)
    try press(session, keyCode: 0x24, characters: "\r")
  }

  private func screen(_ session: any TerminalSession) -> String {
    session.view.accessibilityValue() as? String ?? ""
  }

  /// Catches shell integration that never reaches the protocol, and a running-state query that
  /// does not follow the prompt. The shell reports its directory with OSC 7, which starts at the
  /// first prompt. The query is false there, true while vim runs, and false again after vim quits.
  func testRunningStateFollowsThePromptAndVim() async throws {
    let session = try startShell()
    var directories: [String] = []
    session.onEvent = { event in
      if case .workingDirectoryChanged(let path) = event { directories.append(path) }
    }

    try await waitUntil("the first prompt's working directory") { !directories.isEmpty }
    try await waitUntil("an idle prompt") { !session.isRunningSomething }

    let expected = sandbox.appending(path: "work").resolvingSymlinksInPath().path
    XCTAssertEqual(URL(fileURLWithPath: directories[0]).resolvingSymlinksInPath().path, expected)

    try run("vim -u NONE -N", in: session)
    try await waitUntil("vim's screen") {
      let text = self.screen(session)
      return text.contains("VIM - Vi IMproved")
        || text.split(separator: "\n").filter { $0.hasPrefix("~") }.count >= 3
    }

    try await Task.sleep(for: .milliseconds(500))
    XCTAssertTrue(session.isRunningSomething, "vim is up and the query says idle")

    try press(session, keyCode: 0x35, characters: "\u{1B}")
    try press(session, keyCode: 0x29, characters: ":", modifiers: .shift)
    try press(session, keyCode: 0x0C, characters: "q")
    try press(session, keyCode: 0x12, characters: "!", modifiers: .shift)
    try press(session, keyCode: 0x24, characters: "\r")
    try await waitUntil("the prompt after vim") { !session.isRunningSomething }
  }

  /// Catches OSC 133 marks that never arrive. The shell reports a finished command's exit status,
  /// and the working directory follows `cd`.
  func testCommandFinishedAndDirectoryChangeReachTheProtocol() async throws {
    let session = try startShell()
    var finished: [Int?] = []
    var directories: [String] = []
    session.onEvent = { event in
      switch event {
      case .commandFinished(let code, _): finished.append(code)
      case .workingDirectoryChanged(let path): directories.append(path)
      default: break
      }
    }

    try await waitUntil("an idle prompt") { !session.isRunningSomething && !directories.isEmpty }

    try run("false", in: session)
    try await waitUntil("the exit status of false") { finished.contains(1) }

    try run("true", in: session)
    try await waitUntil("the exit status of true") { finished.contains(0) }

    let target = sandbox.appending(path: "home").resolvingSymlinksInPath().path
    try run("cd \(target)", in: session)
    try await waitUntil("OSC 7 after cd") {
      directories.contains { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path == target }
    }
  }

  /// Catches a missing terminfo or a TERM other than xterm-ghostty. Also checks that the `ssh`
  /// wrapper from the `ssh-env` feature exists, and that a program started by ssh sees
  /// TERM=xterm-256color. The probe uses ssh's ProxyCommand, which runs locally with ssh's own
  /// environment, so no remote host is needed. A real host without the terminfo entry is not
  /// reachable from here.
  func testTermTerminfoAndSshFallback() async throws {
    let session = try startShell()
    try await waitUntil("an idle prompt") { !session.isRunningSomething }

    try run(
      "echo \"T:$TERM:\"; infocmp xterm-ghostty >/dev/null && echo \"I:$((6*7)):\"", in: session)
    try await waitUntil("TERM and infocmp output") {
      let text = self.screen(session)
      return text.contains("T:xterm-ghostty:") && text.contains("I:42:")
    }

    try run("whence -w ssh", in: session)
    try await waitUntil("the ssh wrapper") { self.screen(session).contains("ssh: function") }

    try run(
      "ssh -F /dev/null -o BatchMode=yes -o ProxyCommand='echo \"PT:$TERM:\" >&2; exit 1' nowhere",
      in: session)
    try await waitUntil("the TERM that ssh passes on") {
      self.screen(session).contains("PT:xterm-256color:")
    }
  }

  /// Catches a resize that never reaches the shell. The shell's own `stty size` reports the grid.
  func testShellSeesTheNewSize() async throws {
    let session = try startShell()
    try await waitUntil("an idle prompt") { !session.isRunningSomething }

    let before = session.gridSize
    XCTAssertGreaterThan(before.columns, 20)

    session.resize(to: CGSize(width: 400, height: 200))

    let after = session.gridSize
    XCTAssertLessThan(after.columns, before.columns)
    XCTAssertLessThan(after.rows, before.rows)

    try run("stty size | sed 's/^/S:/;s/ /x/'", in: session)
    let expected = "S:\(after.rows)x\(after.columns)"
    try await waitUntil("stty to report \(expected)") { self.screen(session).contains(expected) }
  }

  /// Catches a pane that stays open after its shell ends.
  func testShellExitEmitsExited() async throws {
    let session = try startShell()
    var exited = false
    session.onEvent = { event in
      if case .exited = event { exited = true }
    }
    try await waitUntil("an idle prompt") { !session.isRunningSomething }

    // libghostty keeps a pane open with an error when its command dies within 250 ms of launch.
    // A plain startup file makes the shell that quick, so wait past the window.
    try await Task.sleep(for: .milliseconds(500))
    try run("exit", in: session)
    try await waitUntil("the exit event") { exited }
    XCTAssertTrue(session.hasExited)
  }

  /// Catches font zoom that does not reach the surface. A bigger font fits fewer columns, and
  /// reset brings the grid back.
  func testFontZoomChangesTheGridAndResets() async throws {
    let session = try startShell()
    try await waitUntil("an idle prompt") { !session.isRunningSomething }
    let original = session.gridSize

    session.perform(.increaseFontSize)
    session.perform(.increaseFontSize)
    XCTAssertLessThan(session.gridSize.columns, original.columns)

    session.perform(.decreaseFontSize)
    session.perform(.decreaseFontSize)
    session.perform(.decreaseFontSize)
    XCTAssertGreaterThan(session.gridSize.columns, original.columns)

    session.perform(.resetFontSize)
    XCTAssertEqual(session.gridSize, original)
  }

  /// Catches copy, paste, and select all that do not work through the protocol. The pasteboard is
  /// saved and restored, since libghostty uses the general one.
  func testCopyPasteAndSelectAll() async throws {
    let saved = NSPasteboard.general.string(forType: .string)
    defer {
      NSPasteboard.general.clearContents()
      if let saved { NSPasteboard.general.setString(saved, forType: .string) }
    }

    let session = try startShell()
    try await waitUntil("an idle prompt") { !session.isRunningSomething }

    try run("echo \"K:$((40+2)):\"", in: session)
    try await waitUntil("the marker") { self.screen(session).contains("K:42:") }

    NSPasteboard.general.clearContents()
    session.perform(.selectAll)
    session.perform(.copy)
    try await waitUntil("the copied text") {
      NSPasteboard.general.string(forType: .string)?.contains("K:42:") == true
    }

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString("echo \"P:$((6*7)):\"", forType: .string)
    session.perform(.paste)
    try press(session, keyCode: 0x24, characters: "\r")
    try await waitUntil("the pasted command's output") { self.screen(session).contains("P:42:") }
  }

  /// Catches OSC 9 and OSC 777 notifications that do not reach the protocol.
  func testNotificationsReachTheProtocol() async throws {
    let session = try startShell()
    var notes: [String] = []
    session.onEvent = { event in
      if case .notification(let title, let body) = event { notes.append("\(title)|\(body)") }
    }
    try await waitUntil("an idle prompt") { !session.isRunningSomething }

    try run("printf '\\033]9;nine-body\\a'", in: session)
    try await waitUntil("the OSC 9 notification") { !notes.isEmpty }

    // libghostty allows one notification per second.
    try await Task.sleep(for: .milliseconds(1_200))
    try run("printf '\\033]777;notify;sevens-title;sevens-body\\a'", in: session)
    try await waitUntil("the OSC 777 notification") { notes.count >= 2 }

    XCTAssertTrue(notes.contains("|nine-body"), "got \(notes)")
    XCTAssertTrue(notes.contains("sevens-title|sevens-body"))
  }

  /// Catches an OSC 52 clipboard read that is answered before the user decides. The request waits.
  /// While it waits, the program receives nothing. An allowed request then sends the clipboard, and
  /// a denied one sends none of it.
  func testClipboardReadIsNeverAnsweredWithoutConfirmation() async throws {
    let saved = NSPasteboard.general.string(forType: .string)
    defer {
      NSPasteboard.general.clearContents()
      if let saved { NSPasteboard.general.setString(saved, forType: .string) }
    }

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString("SECRET-CB", forType: .string)
    let encoded = Data("SECRET-CB".utf8).base64EncodedString()

    let session = try startShell()
    var requests: [TerminalClipboardRequest] = []
    session.onEvent = { event in
      if case .clipboardRequest(let request) = event { requests.append(request) }
    }
    try await waitUntil("an idle prompt") { !session.isRunningSomething }

    // The shell reads the terminal's reply itself, so the output shows what the program received.
    let ask =
      "printf '\\033]52;c;?\\a'; IFS= read -rs -t 8 -d $'\\\\' reply; echo \"G:${reply#*;c;}:\""

    try run(ask, in: session)
    try await waitUntil("the clipboard request") { !requests.isEmpty }
    XCTAssertEqual(requests[0].kind, .read)

    try await Task.sleep(for: .seconds(1))
    XCTAssertTrue(session.isRunningSomething, "the program got its answer before confirmation")
    XCTAssertFalse(screen(session).contains(encoded), "the clipboard was sent before confirmation")

    requests[0].resolve(allow: false)
    try await waitUntil("the read to finish after a denial") { !session.isRunningSomething }
    XCTAssertFalse(screen(session).contains(encoded), "a denied read still sent the clipboard")

    try run(ask, in: session)
    try await waitUntil("the second request") { requests.count == 2 }
    requests[1].resolve(allow: true)
    try await waitUntil("the clipboard after confirmation") {
      self.screen(session).contains(encoded)
    }
  }

  /// Catches libghostty bindings that survive in the generated config. With them, Cmd-Z, Cmd-W,
  /// Cmd-T, Cmd-D, and Cmd-Q would be taken by the terminal before uniterm's menu.
  func testBuiltInBindingsAreCleared() throws {
    let session = try startShell()
    let view = try XCTUnwrap(session.view as? GhosttySurfaceView)

    let keys: [(UInt16, Character)] = [
      (0x06, "z"), (0x0D, "w"), (0x11, "t"), (0x02, "d"), (0x0C, "q"),
    ]
    for (code, character) in keys {
      XCTAssertFalse(
        view.isLibraryBinding(keyCode: code, character: character, mods: .command),
        "Cmd-\(character) is still a libghostty binding")
    }
  }

  private var configFile: URL {
    sandbox.appending(path: "config/ghostty-\(getpid()).conf")
  }

  /// Catches a palette change that never reaches a running surface. The engine writes the new
  /// config, and libghostty announces that it applied it to the surface. The announcement stops
  /// when the `ghostty_app_update_config` call is removed.
  ///
  /// What this cannot prove is the color on screen, since libghostty has no call to read a
  /// surface's colors. That stays a check for the user.
  func testPaletteChangeReachesTheConfigFileAndTheRunningSurface() async throws {
    let session = try startShell()
    let view = try XCTUnwrap(session.view as? GhosttySurfaceView)
    let latte = try String(contentsOf: configFile, encoding: .utf8)
    XCTAssertTrue(latte.contains("background = #eff1f5"))

    let before = view.configChangeCount
    try engine.apply(palette: .mocha)

    let mocha = try String(contentsOf: configFile, encoding: .utf8)
    XCTAssertTrue(mocha.contains("background = #1e1e2e"))
    XCTAssertFalse(mocha.contains("background = #eff1f5"))
    try await waitUntil("the surface to apply the Mocha config") { view.configChangeCount > before }

    let afterMocha = view.configChangeCount
    try engine.apply(palette: .latte)
    try await waitUntil("the surface to apply the Latte config") {
      view.configChangeCount > afterMocha
    }
    XCTAssertTrue(try String(contentsOf: configFile, encoding: .utf8).contains("#eff1f5"))
  }

  /// An equal palette is skipped, so the surface is not told twice.
  func testApplyingTheSamePaletteTwiceDoesNotReloadTheSurface() async throws {
    let session = try startShell()
    let view = try XCTUnwrap(session.view as? GhosttySurfaceView)

    try engine.apply(palette: .latte)
    try await Task.sleep(for: .milliseconds(300))

    XCTAssertEqual(view.configChangeCount, 0)
  }

  /// The direct children of a process, by pid. The unused tail of the buffer stays zero.
  private func children(of parent: pid_t) -> [pid_t] {
    var buffer = [pid_t](repeating: 0, count: 256)
    let result = proc_listchildpids(parent, &buffer, Int32(buffer.count * MemoryLayout<pid_t>.size))
    return result > 0 ? Array(buffer.prefix { $0 > 0 }) : []
  }

  private func tree(of root: pid_t) -> [pid_t] {
    var found = [root]
    var index = 0

    while index < found.count {
      for child in children(of: found[index]) where !found.contains(child) {
        found.append(child)
      }

      index += 1
    }

    return found
  }

  /// Guards the main thread against a hung close. libghostty hangs the child up with SIGHUP and
  /// loops until the child it tracks is gone. A shell that ignores SIGHUP might keep that loop
  /// running for good, and the free runs on the main thread.
  ///
  /// The trace found no hang. libghostty tracks `login(1)`, which exits on SIGHUP, so `close()`
  /// returns at once. The shell and its `sleep` survive, as `nohup` work does after any terminal
  /// closes. This test passed before any change and stays as a guard. A rescue kills the tree
  /// after 8 seconds so that a regression cannot hang the suite. The test ends the tree itself.
  func testCloseReturnsWhenTheChildIgnoresSIGHUP() async throws {
    let before = Set(children(of: getpid()))
    let session = try startShell()
    try await waitUntil("an idle prompt") { !session.isRunningSomething }

    let child = try XCTUnwrap(
      Set(children(of: getpid())).subtracting(before).first, "the session's child was not found")

    try run("trap '' HUP; sleep 1000", in: session)
    try await waitUntil("sleep to run") { session.isRunningSomething }
    try await Task.sleep(for: .milliseconds(300))

    let members = tree(of: child)
    XCTAssertGreaterThan(members.count, 2, "no sleep under the shell")
    defer {
      for pid in members.reversed() {
        kill(pid, SIGKILL)
      }
    }

    let rescue = DispatchWorkItem {
      for pid in members.reversed() {
        kill(pid, SIGKILL)
      }
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: rescue)

    let started = ContinuousClock.now
    session.close()
    rescue.cancel()
    let elapsed = ContinuousClock.now - started

    XCTAssertLessThan(elapsed, .seconds(3), "close() blocked the main thread for \(elapsed)")
  }

  /// Catches a spawned shell that cannot use the home folder, as a sandbox would force. The shell
  /// writes a file under `$HOME`, reads it back, and the file is removed.
  func testShellCanReadAndWriteHome() async throws {
    let name = ".uniterm-test-\(UUID().uuidString)"
    let file = FileManager.default.homeDirectoryForCurrentUser.appending(path: name)
    defer { try? FileManager.default.removeItem(at: file) }

    let session = try startShell()
    try await waitUntil("an idle prompt") { !session.isRunningSomething }

    let token = "wrote-\(UUID().uuidString.prefix(8))"
    try run(
      "printf %s \(token) > \"$HOME/\(name)\" && echo \"H:$(cat \"$HOME/\(name)\"):\"", in: session)
    try await waitUntil("the file's contents") { self.screen(session).contains("H:\(token):") }

    XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), token)
  }

  /// Catches a real key path that drops the apostrophe. keyCode 39 then Space types an apostrophe
  /// on US and on US Extended, where the apostrophe is a dead key that Space completes. The
  /// events go through `keyDown` and the text input system, as typing does.
  func testApostropheTypedThroughKeyDownReachesTheShell() async throws {
    let session = try startShell()
    try await waitUntil("an idle prompt") { !session.isRunningSomething }

    try press(session, keyCode: 39, characters: "'")
    try press(session, keyCode: 49, characters: " ")

    try await waitUntil("an apostrophe at the prompt") { self.screen(session).contains("% '") }
  }

  /// The menu reaches the terminal with a nil target, so AppKit finds `copy:` and the others on
  /// the first responder and asks `validateMenuItem` whether to enable them. This drives that path
  /// in-process. The pasteboard is saved and restored.
  func testMenuActionsReachTheFocusedTerminal() async throws {
    let saved = NSPasteboard.general.string(forType: .string)
    defer {
      NSPasteboard.general.clearContents()
      if let saved { NSPasteboard.general.setString(saved, forType: .string) }
    }

    let session = try startShell()
    let view = try XCTUnwrap(session.view as? GhosttySurfaceView)
    XCTAssertTrue(window.makeFirstResponder(view))
    try await waitUntil("an idle prompt") { !session.isRunningSomething }

    let copyItem = NSMenuItem(
      title: "Copy", action: #selector(TerminalMenuActions.copy(_:)), keyEquivalent: "c")
    XCTAssertFalse(view.validateMenuItem(copyItem), "Copy is enabled with nothing selected")

    try run("echo \"M:$((6*7)):\"", in: session)
    try await waitUntil("the marker") { self.screen(session).contains("M:42:") }

    XCTAssertTrue(view.tryToPerform(#selector(TerminalMenuActions.selectAll(_:)), with: nil))
    XCTAssertTrue(view.validateMenuItem(copyItem), "Copy is disabled with a selection")

    NSPasteboard.general.clearContents()
    XCTAssertTrue(view.tryToPerform(#selector(TerminalMenuActions.copy(_:)), with: nil))
    try await waitUntil("the copied text") {
      NSPasteboard.general.string(forType: .string)?.contains("M:42:") == true
    }

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString("echo \"V:$((5*9)):\"", forType: .string)
    XCTAssertTrue(view.tryToPerform(#selector(TerminalMenuActions.paste(_:)), with: nil))
    try press(session, keyCode: 0x24, characters: "\r")
    try await waitUntil("the pasted command's output") { self.screen(session).contains("V:45:") }

    let columns = session.gridSize.columns
    XCTAssertTrue(
      view.tryToPerform(#selector(TerminalMenuActions.increaseTerminalFontSize(_:)), with: nil))
    XCTAssertLessThan(session.gridSize.columns, columns)
    XCTAssertTrue(
      view.tryToPerform(#selector(TerminalMenuActions.resetTerminalFontSize(_:)), with: nil))
    XCTAssertEqual(session.gridSize.columns, columns)

    XCTAssertTrue(
      view.tryToPerform(#selector(TerminalMenuActions.clearTerminalScreen(_:)), with: nil))
    try await waitUntil("the cleared screen") { !self.screen(session).contains("M:42:") }
  }
}

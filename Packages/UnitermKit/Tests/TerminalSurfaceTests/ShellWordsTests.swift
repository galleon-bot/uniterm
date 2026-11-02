import XCTest

@testable import TerminalSurface

final class ShellWordsTests: XCTestCase {
  /// Catches a splitter that breaks words at the wrong place. Expected words are written out by
  /// hand: quotes group, quote marks vanish, and a backslash keeps the next character.
  func testSplitsLikeAShellForQuotesAndBackslashes() throws {
    let cases: [(String, [String])] = [
      ("vim", ["vim"]),
      ("  ssh   -p  2222  host ", ["ssh", "-p", "2222", "host"]),
      ("tail -f 'my log.txt'", ["tail", "-f", "my log.txt"]),
      (#"echo "a  b" c"#, ["echo", "a  b", "c"]),
      (#"echo a\ b"#, ["echo", "a b"]),
      (#"echo "say \"hi\"""#, ["echo", #"say "hi""#]),
      (#"echo "back\slash""#, ["echo", #"back\slash"#]),
      (#"echo "cost \$5""#, ["echo", "cost $5"]),
      ("echo 'it'\"'\"'s'", ["echo", "it's"]),
      ("echo ''", ["echo", ""]),
      ("echo 'a|b;c*d$e' x#y a~b", ["echo", "a|b;c*d$e", "x#y", "a~b"]),
      (#"echo \| \* \~"#, ["echo", "|", "*", "~"]),
      ("sh -c 'echo \"$1\"; read x' sh arg", ["sh", "-c", #"echo "$1"; read x"#, "sh", "arg"]),
    ]

    for (line, expected) in cases {
      XCTAssertEqual(try ShellWords.split(line), expected, line)
    }
  }

  /// Catches a line that a shell would read as more than one program or as an expansion, which
  /// program mode would otherwise run as something the user did not type.
  func testRefusesShellSyntaxThatIsNotQuoted() {
    let cases: [(String, ShellWordsError)] = [
      ("ls | less", .shellSyntax("|")),
      ("a && b", .shellSyntax("&")),
      ("a; b", .shellSyntax(";")),
      ("a > out", .shellSyntax(">")),
      ("a < in", .shellSyntax("<")),
      ("echo $HOME", .shellSyntax("$")),
      (#"echo "$HOME""#, .shellSyntax("$")),
      ("echo `id`", .shellSyntax("`")),
      ("ls *.txt", .shellSyntax("*")),
      ("ls ?", .shellSyntax("?")),
      ("rm -rf ~", .shellSyntax("~")),
      ("# comment", .shellSyntax("#")),
      ("f (x)", .shellSyntax("(")),
      ("echo {a,b}", .shellSyntax("{")),
    ]

    for (line, expected) in cases {
      XCTAssertThrowsError(try ShellWords.split(line), line) {
        XCTAssertEqual($0 as? ShellWordsError, expected, line)
      }
    }
  }

  /// Catches a line with no program, a broken quote, or a second line, which would reach libghostty
  /// as a malformed command.
  func testRefusesLinesThatCannotBeOneProgram() {
    let cases: [(String, ShellWordsError)] = [
      ("", .empty),
      ("   ", .empty),
      ("''", .empty),
      ("echo 'open", .unterminatedQuote("'")),
      (#"echo "open"#, .unterminatedQuote("\"")),
      ("echo trailing\\", .danglingEscape),
      ("a\nb", .multipleLines),
      ("echo 'a\nb'", .multipleLines),
      ("a\u{0}b", .nulCharacter),
    ]

    for (line, expected) in cases {
      XCTAssertThrowsError(try ShellWords.split(line), line) {
        XCTAssertEqual($0 as? ShellWordsError, expected, line)
      }
    }
  }

  /// Catches quoting that lets an argument reach a shell as syntax. libghostty runs the program
  /// through `/bin/sh -c`, so the quoted string must read back through a real sh as exactly the
  /// words that went in. The words hold a space, a quote, a semicolon, a glob, a variable, and a
  /// newline. The environment is empty, so sh reads no startup file.
  func testQuotedWordsReadBackThroughAShellExactly() throws {
    let words = [
      "plain", "two words", "it's", "a;b", "*", "$HOME", "`id`", "line\nbreak", "", "'", "\\",
    ]

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", "printf '<%s>' " + ShellWords.quote(words)]
    process.environment = ["HOME": "/nonexistent"]

    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()

    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    XCTAssertEqual(process.terminationStatus, 0)
    XCTAssertEqual(
      String(decoding: output, as: UTF8.self), words.map { "<\($0)>" }.joined())
  }

  /// Catches the ssh fallback applying to the wrong programs. A program whose basename is exactly
  /// `ssh` gets TERM=xterm-256color, by name or by path. Names that only contain ssh do not.
  func testOnlyASshProgramGetsAFallbackTerm() {
    let cases: [([String], String?)] = [
      (["ssh", "host"], "xterm-256color"),
      (["/usr/bin/ssh", "host"], "xterm-256color"),
      (["./ssh"], "xterm-256color"),
      (["ssh-keygen"], nil),
      (["sshd"], nil),
      (["myssh"], nil),
      (["mosh", "ssh"], nil),
      (["vim", "ssh"], nil),
    ]

    for (words, expected) in cases {
      let launch = TerminalLaunch.program(words)
      XCTAssertEqual(launch.environment["TERM"], expected, "\(words)")
      XCTAssertEqual(launch.program, words)
    }
  }

  /// Catches a fallback that replaces the caller's environment instead of adding to it.
  func testSshFallbackKeepsTheCallersEnvironment() {
    let launch = TerminalLaunch.program(
      ["ssh", "host"], environment: ["LANG": "C"], version: "9.9")

    XCTAssertEqual(
      launch.environment,
      [
        "LANG": "C", "TERM": "xterm-256color", "TERM_PROGRAM": "uniterm",
        "TERM_PROGRAM_VERSION": "9.9",
      ])
  }

  /// Catches a launch that leaves libghostty's `TERM_PROGRAM=ghostty` in place. Both factories add
  /// uniterm's name and the given version, and a variable from the caller still replaces them.
  func testLaunchesReportUnitermAndItsVersion() {
    let shell = TerminalLaunch.loginShell(version: "1.2.3")
    let program = TerminalLaunch.program(["vim"], version: "1.2.3")
    let expected = ["TERM_PROGRAM": "uniterm", "TERM_PROGRAM_VERSION": "1.2.3"]

    XCTAssertEqual(shell.environment, expected)
    XCTAssertEqual(program.environment, expected)

    let overridden = TerminalLaunch.loginShell(
      environment: ["TERM_PROGRAM": "other"], version: "1.2.3")
    XCTAssertEqual(overridden.environment["TERM_PROGRAM"], "other")
  }
}

import XCTest

@testable import TerminalSurface

final class InheritedEnvironmentTests: XCTestCase {
  private func scrub(_ environment: [String: String]) -> (
    kept: Set<String>, removed: [String: String]
  ) {
    var live = environment
    let removed = InheritedEnvironment.scrub(environment: environment) { live[$0] = nil }
    return (Set(live.keys), removed)
  }

  /// Catches a scrub list that misses noise a shell would inherit, and one that removes what the
  /// user's session needs. Every listed name and prefix goes. `PATH`, `SSH_AUTH_SOCK`, `LANG`, and
  /// the names libghostty overwrites anyway stay.
  func testListedVariablesAreRemovedAndOthersStay() {
    let noise = [
      "MAKEFLAGS", "MFLAGS", "MAKELEVEL", "MAKE_TERMOUT", "MAKE_TERMERR", "TERM_SESSION_ID",
      "ITERM_SESSION_ID", "ITERM_PROFILE", "TMUX", "TMUX_PANE", "KITTY_WINDOW_ID", "WEZTERM_PANE",
      "ALACRITTY_WINDOW_ID", "GHOSTTY_RESOURCES_DIR", "GHOSTTY_BIN_DIR", "UNITERM_LAYOUT_DIR",
    ]
    let kept = ["PATH", "SSH_AUTH_SOCK", "LANG", "HOME", "TERM", "TERM_PROGRAM", "COLORTERM"]

    let result = scrub(Dictionary(uniqueKeysWithValues: (noise + kept).map { ($0, "x") }))

    XCTAssertEqual(result.kept, Set(kept))
    XCTAssertEqual(Set(result.removed.keys), Set(noise))
  }

  /// Catches a scrub that drops `UNITERM_` values before the app can read them. The values come
  /// back in the result, and the variables are gone from the live environment.
  func testUnitermVariablesAreReturnedAfterBeingRemoved() {
    let result = scrub(["UNITERM_DEFAULTS_PATH": "/tmp/d.plist", "PATH": "/usr/bin"])

    XCTAssertEqual(result.removed, ["UNITERM_DEFAULTS_PATH": "/tmp/d.plist"])
    XCTAssertEqual(result.kept, ["PATH"])
  }

  /// Catches a prefix match that is looser than the listed prefixes. A name that only contains
  /// the prefix, or differs by case, stays.
  func testPrefixesMatchOnlyAtTheStart() {
    let result = scrub(["MY_GHOSTTY_X": "1", "ghostty_x": "1", "UNITERMS": "1", "MAKEFLAGS2": "1"])

    XCTAssertEqual(result.kept, ["MY_GHOSTTY_X", "ghostty_x", "UNITERMS", "MAKEFLAGS2"])
    XCTAssertTrue(result.removed.isEmpty)
  }

  /// Catches a process scrub that does not reach the real environment.
  func testScrubProcessUnsetsRealVariables() {
    setenv("MAKELEVEL", "3", 1)
    setenv("UNITERM_TEST_KNOB", "on", 1)
    defer {
      unsetenv("MAKELEVEL")
      unsetenv("UNITERM_TEST_KNOB")
    }

    let removed = InheritedEnvironment.scrubProcess()

    XCTAssertEqual(removed["MAKELEVEL"], "3")
    XCTAssertEqual(removed["UNITERM_TEST_KNOB"], "on")
    XCTAssertNil(getenv("MAKELEVEL"))
    XCTAssertNil(getenv("UNITERM_TEST_KNOB"))
  }
}

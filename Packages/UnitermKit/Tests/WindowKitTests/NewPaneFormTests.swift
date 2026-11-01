import XCTest

@testable import WindowKit

final class NewPaneFormTests: XCTestCase {
  /// Catches a default that needs typing. A new form is a shell terminal, so Return alone opens
  /// one.
  func testTheDefaultChoiceIsAShell() {
    XCTAssertEqual(NewPaneForm().choice, .terminalShell)
  }

  /// Catches program mode that starts with nothing to run, or that keeps stray space around the
  /// command.
  func testProgramModeNeedsACommandAndTrimsIt() {
    var form = NewPaneForm()
    form.mode = .program
    XCTAssertNil(form.choice)

    form.command = "  \n "
    XCTAssertNil(form.choice)

    form.command = "  tail -f log \n"
    XCTAssertEqual(form.choice, .terminalProgram(command: "tail -f log"))
  }

  /// Catches a leftover command that turns a shell choice into a program.
  func testShellModeIgnoresTheCommand() {
    var form = NewPaneForm()
    form.command = "htop"

    XCTAssertEqual(form.choice, .terminalShell)
  }
}

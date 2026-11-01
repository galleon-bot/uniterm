import Foundation

/// What the user asked a new pane to run.
public enum AppletChoice: Sendable, Equatable {
  /// A terminal that starts the user's login shell.
  case terminalShell

  /// A terminal that runs one program, given as a command line.
  case terminalProgram(command: String)
}

/// The state of the new-pane picker, apart from its views.
struct NewPaneForm: Equatable {
  enum Mode: Int, CaseIterable {
    case shell
    case program

    var title: String {
      switch self {
      case .shell: return "Terminal"
      case .program: return "Terminal running a program"
      }
    }
  }

  var mode: Mode = .shell
  var command = ""

  /// The choice the form describes, or nil while it is incomplete. A program needs a command.
  var choice: AppletChoice? {
    switch mode {
    case .shell:
      return .terminalShell

    case .program:
      let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : .terminalProgram(command: trimmed)
    }
  }
}

import Foundation

/// How uniterm introduces itself to programs in a terminal.
///
/// libghostty sets `TERM_PROGRAM=ghostty` for every child. uniterm's launch variables are applied
/// after it, so these values win. The `ssh-env` shell-integration feature forwards `TERM_PROGRAM`
/// to remote hosts, so the name must be uniterm's own.
public enum TerminalIdentity {
  public static let programName = "uniterm"

  /// The app bundle's short version string, which `MARKETING_VERSION` sets in the Xcode project.
  /// Code that runs outside the app bundle sees the host process's version instead.
  public static var bundleVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
  }

  /// The variables every terminal launch carries.
  public static func environment(version: String) -> [String: String] {
    ["TERM_PROGRAM": programName, "TERM_PROGRAM_VERSION": version]
  }
}

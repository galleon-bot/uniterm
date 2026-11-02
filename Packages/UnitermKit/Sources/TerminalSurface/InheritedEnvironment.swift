import Foundation

/// The variables uniterm removes from its own process environment before any terminal exists.
///
/// Every terminal inherits uniterm's whole environment, and libghostty adds its own variables on
/// top. A launch's `environment` can add or replace a variable but never remove one. The only way
/// to keep a variable out of every shell is to unset it here, at startup.
///
/// Everything not listed stays, including `PATH`, `SSH_AUTH_SOCK`, and `LANG`. libghostty
/// overwrites `TERM`, `COLORTERM`, `TERM_PROGRAM`, and `TERM_PROGRAM_VERSION` for every child, so
/// those need no entry.
public enum InheritedEnvironment {
  /// Variables that describe the process that started uniterm, not the user's session.
  ///
  /// - `MAKEFLAGS` and friends: a `make run` leaves them behind. A shell that runs `make` then
  ///   inherits the parent's jobserver and flags.
  /// - Other terminals' session variables: they name a window, tab, or pane of a terminal that
  ///   does not host this shell. Programs such as `tmux` and `wezterm` act on them.
  public static let names: Set<String> = [
    "MAKEFLAGS", "MFLAGS", "MAKELEVEL", "MAKE_TERMOUT", "MAKE_TERMERR",
    "TERM_SESSION_ID", "ITERM_SESSION_ID", "ITERM_PROFILE",
    "TMUX", "TMUX_PANE",
    "KITTY_WINDOW_ID", "WEZTERM_PANE", "ALACRITTY_WINDOW_ID",
  ]

  /// Name prefixes that are removed whole.
  ///
  /// - `GHOSTTY_`: a uniterm started from Ghostty, or from a uniterm shell, inherits Ghostty's
  ///   state. `GHOSTTY_RESOURCES_DIR` would win over uniterm's own bundle. The engine sets the
  ///   variable again from uniterm's bundle after this runs.
  /// - `UNITERM_`: debug-only knobs that uniterm reads once. `scrub` returns them, so the reader
  ///   cannot run after they are gone.
  public static let prefixes = ["GHOSTTY_", "UNITERM_"]

  public static func isScrubbed(_ name: String) -> Bool {
    names.contains(name) || prefixes.contains { name.hasPrefix($0) }
  }

  /// Unsets every scrubbed variable of the given environment, and returns what it removed.
  /// Callers read the removed `UNITERM_` values from the result.
  public static func scrub(
    environment: [String: String], unset: (String) -> Void
  ) -> [String: String] {
    var removed: [String: String] = [:]

    for (name, value) in environment where isScrubbed(name) {
      unset(name)
      removed[name] = value
    }

    return removed
  }

  /// Scrubs this process's environment. Call it once, before the engine starts, and before
  /// anything else in the process starts a thread that reads the environment.
  public static func scrubProcess() -> [String: String] {
    scrub(environment: ProcessInfo.processInfo.environment) { unsetenv($0) }
  }
}

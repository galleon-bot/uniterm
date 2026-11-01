# UTERM-001 M1-M9: Foundation work-queue run

Started 2026-10-31. This report covers a `/work-queue` run of the queue row `UTERM-001 M1-M9`. UTERM-001 is
uniterm's foundation proposal, at `spec/proposals/UTERM-001-foundation.md`. The specs live in the code repo, so every
commit below is in `/Users/ripta/projects/uniterm`. The branch is `agent/petunia/uterm-001`.

## TL;DR

The run is in progress. See the run state below.

## Run state

- Base commit for the run and for the row: "Schedule UTERM-001 M1-M9 as the first queue row"
- Specs commits: the specs live in the code repo, so the milestone commits are the specs commits

| Milestone | Run status | Commit |
|-----------|------------|--------|
| M1 App skeleton and theme tokens | DONE | "Add the app skeleton, pinned Ghostty build, and theme tokens" |
| M2 Terminal applet in a single pane | DONE | "Add the terminal applet behind a libghostty surface protocol" |
| M3 Pane tree | QUEUED | |
| M4 Status bar region | QUEUED | |
| M5 Terminal tabs and program mode | QUEUED | |
| M6 Multiple windows | QUEUED | |
| M7 Undo close pane | QUEUED | |
| M8 Layout persistence | QUEUED | |
| M9 User visual check | HELD: a check only the user can perform | |

Held or blocked rows: none. M9 is left to the user. The row stays in `queue.md` until the user records it.

## Environment

- macOS 26.6.2 (25G83), Xcode 26.6 (17F113), SDK 26.5, Swift 6.3.3, Zig 0.15.2 from Homebrew
- Ghostty pin: tag v1.3.1, peeled commit `332b2aefc6e72d363aa93ab6ecfc86eeeeb5ed28`. `build.zig.zon` declares
  `minimum_zig_version = "0.15.2"`

## Run-level best guesses

These come from the approved plan at `/Users/ripta/.claude/plans/harmonic-herding-dewdrop.md`.

- Pin Ghostty v1.3.1. Fall back to v1.3.0 (`703d11c6`) if it does not build with Xcode 26.6.
- Swift 6 language mode with strict concurrency, in both the package and the app.
- M2 builds the full status message model. M4 renders it.
- Formatter and linter: `swift format` from the toolchain.
- Tunable bounds get concrete values chosen by the implementer and recorded in As built.
- M9 is left to the user.

## Milestones

### M1: App skeleton and theme tokens

Commit: "Add the app skeleton, pinned Ghostty build, and theme tokens".

Checks:
- `make fmt-check`, `make lint`, `make check`, `make build`, and `make test` all pass. `make test` ran 12 package
  tests and 3 UI tests. `make ghostty-offline-check` passes, and `make ci` now runs it.
- `proposals.py check` and `proposals.py freeze` both print `[]`.
- `xcrun`, `swift`, and `xcodebuild` fail in the Bash sandbox with "couldn't create cache file", so every check ran
  unsandboxed.

Best guesses from the implementer:
- Zig 0.15.2 cannot link against the macOS 26 SDK. The SDK's libSystem stub lists only `arm64e`.
  - The build puts an `xcrun` shim on Zig's PATH. It answers `--show-sdk-path` with the Command Line Tools SDK
    `MacOSX15.4.sdk`, and passes every other query through.
  - The pin records `ZIG_SDK_VERSION=15.4`.
  - If this is wrong, a machine without that Command Line Tools SDK cannot build Ghostty. A Zig bump would remove the
    shim.
- Xcode 26.6's `libtool` silently drops Zig's archive members. A `libtool` shim extracts each input archive and
  combines the loose objects. It fails when the member count and the extracted count differ.
- Ghostty's build needs the Metal toolchain component. The implementer ran `xcodebuild -downloadComponent
  MetalToolchain`, a 688 MB system-wide install outside the repo. The README lists it as a prerequisite.
- The Ghostty source is a codeload tarball fetched by commit. A tree hash, `GHOSTTY_TREE_SHA256` in `ghostty.pin`,
  verifies the extracted files. `scripts/build-ghostty.sh tree-hash` computes it on a pin bump.
- The bundle ID is `dev.uniterm.app`, since the project names no owner domain.
- The modules are Theme, Preferences, WindowKit, SettingsKit, and TerminalSurface. The settings types are named
  `SettingKey` and `SettingsStore`, since SwiftUI owns `PreferenceKey`.
- `Package.swift` calls `fatalError` naming `make build` when the xcframework link is missing.
- The UI tests isolate preferences through `UNITERM_DEFAULTS_PATH`.
- The deinits use `isolated deinit`, which is Swift 6.2 syntax.

Deviations:
- Hardened runtime is set, but Xcode ignores it under ad hoc signing.
- No UI test can prove the chrome reacts to an out-of-process `defaults write`. The UI test runner is sandboxed, and
  its writes never notify the app. `swift test` covers the store's reaction to a real `defaults` child process. The
  window's reaction was checked by hand on a launched binary.

Review findings, all fixed:

| # | Finding | Disposition |
|---|---------|-------------|
| 1 | The tarball had no integrity check | Trace confirmed, fixed with a tree hash |
| 2 | Stale-lock takeover race | Trace confirmed, replaced with a kernel `flock` |
| 3 | No evidence for the relink check or the interrupted-build check | Fixed. Both demonstrated, see As built |
| 4 | The offline check was outside `make ci`, and SIGINT could delete the artifact | Fixed. Tested with SIGINT |
| 5 | UI tests wrote real preferences | Confirmed, fixed |
| 6 | No automated test of an external `defaults write` | Recorded as a gap. The runner's sandbox prevents it |
| 7 | Duplicate archive member names in the libtool shim | Not confirmed in practice. A guard was added. Diagnosis unresolved |
| 8 | Misplaced comment | Fixed |
| 9 | `watch(_:)` was not idempotent | Confirmed by a failing test first, then fixed |

adr-impact: no conflicts and no supersessions. It found no uncovered decision that meets the ADR bar.

Checks left to the user:
- Flip the system appearance while the setting is System, and confirm the chrome follows.
- Open the project in the Xcode UI on a cold checkout, and confirm the error names `make build`.
- Confirm the "no GUI or no Accessibility" message of `make test`. It never fired here, since the UI tests ran.

Test cost: `swift test` 0.4 s of test time, UI tests 15.6 s, `make test` about 24 s. A cold Ghostty build and the
offline rebuild take about 4 minutes each. The Zig cache is 483 MB.

Leftovers: a hook blocked the implementer's `rm -r`. The git-ignored `.cache/scratch`, `.cache/ghostty-src`, and
`.cache/ghostty/lock` are dead and can be deleted by hand.

### M2: Terminal applet in a single pane

Commit: "Add the terminal applet behind a libghostty surface protocol".

Checks:
- The implementer ran `make fmt-check`, `make lint`, `make check`, `make build`, and `make test-package`, and all
  passed.
- The coordinator reran `make test-package` independently: 100 tests, 0 failures, 4 skipped. The 4 skips are the
  key-translation tests that assert US-layout codepoints. The user's layout is US Extended.
- The coordinator ran the UI suite once on a quiet desktop with `make test-app`: 11 tests, 0 failures, 52 s. The screen
  captured by the resize test showed `A:34x119:` before the resize and `B:25x82:` after it.
- The user typed `echo 'a' "b"` on a real keyboard in the built app and saw `a b`.
- `proposals.py check` and `proposals.py freeze` both print `[]`.

Best guesses from the implementer:
- The new modules are StatusKit, AppletKit, and TerminalApplet. The protocols are `TerminalEngine` and
  `TerminalSession`.
- libghostty's C API surfaces only the OSC 133 command-finished mark. The protocol carries a `commandFinished` event,
  plus a running-state query that follows the prompt marks. The proposal's protocol decision and one M2 check were
  amended to match. ADR-01 says "prompt marks", and adr-impact judged it consistent. ADR-01 was not edited.
- The config builder rejects unsafe values instead of escaping them. It uses an allow list of keys and a safe value
  alphabet.
- The config file is per instance, at `~/Library/Application Support/uniterm/terminal/ghostty-<pid>.conf`. Stale files
  from dead pids are removed at engine start.
- The C callbacks hop to the main actor asynchronously. A surface freed inside its own close callback would be a use
  after free.
- The clipboard alert names the pane, with Cancel as the default. A denial completes with empty data.
- The status bounds are a 1.5 s dwell, a 5 s idle timeout, a skip above a backlog of 3, and a history of 500.
- Cmd-T, Cmd-D, and Cmd-Z post "not available yet" until their milestones land.
- `UNITERM_TERMINAL_DIR` is honored only in DEBUG builds.

Deviations: none beyond the amendment above. The close guard is M7's, so Cmd-W and Cmd-Q do not ask yet.

Review findings, first round:

| # | Finding | Disposition |
|---|---------|-------------|
| 1 | `WindowChromeUITests` ran the developer's real shell | Fixed with a shared launch helper |
| 2 | Cmd-W no longer closed Settings, a regression from M1 | Fixed. A unit test fails without the fix |
| 3 | UI flakes, with a suspected main-thread hang on close | Hang not confirmed. Diagnosis unresolved. Teardown and activation added |
| 4 | The palette test passed vacuously | Fixed. It fails when the update call is removed |
| 5 | The vim test never confirmed vim was up | Fixed |
| 6 | The apostrophe cause was unproven, and the real key path was untested | Fixed. A real key-path test and a user check were added |
| 7 | Amendment markers were missing, and As built held a path list | Fixed |
| 8 | A milestone name in a code comment, and a dense test doc | Fixed |
| 9 | No evidence for the sandbox and `$HOME` check or the menu path | Fixed |
| 10 | The ssh probe read `~/.ssh/config` | Fixed with `-F /dev/null` |
| 11 | Minor config-store and test-comment items | Fixed |

User-raised issues during M2:
- The UI test typed `'`, which arrived as `;5u`. XCUITest delivered the key with the Control flag (`flags=262144`).
  The real key path is correct, and the user confirmed it on a real keyboard. Why XCUITest adds Control on US Extended
  is unresolved.
- Tests that spawned a shell ran the user's dotfiles and prompted for an SSH passphrase. Every shell a test spawns is
  now isolated.

adr-impact: no conflicts and no supersessions. Two ADR candidates were recorded as Undecided in the proposal's Decision
Log: the applet contract, and the clipboard-read confirmation policy.

Checks left to the user:
- One real ssh session to a host without the `xterm-ghostty` terminfo entry.
- A live system appearance change reaching the terminal palette.
- The on-screen colors after a palette change.

Process notes:
- The implementer ran `git checkout App/AppDelegate.swift` mid-work, which discarded its own edits. It rewrote the
  file, and the reviewer found it coherent.
- Debug runs left 15 orphaned `sleep 1000` processes. They exit on their own after about 17 minutes.

Test cost: `swift test` takes 7.4 s of test time for 100 tests. The UI suite takes 52 s.

## Status

In progress.

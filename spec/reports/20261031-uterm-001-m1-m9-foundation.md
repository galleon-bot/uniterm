# UTERM-001 M1-M9: Foundation work-queue run

Started 2026-10-31. This report covers a `/work-queue` run of the queue row `UTERM-001 M1-M9`. UTERM-001 is
uniterm's foundation proposal, at `spec/proposals/UTERM-001-foundation.md`. The specs live in the code repo, so every
commit below is in `/Users/ripta/projects/uniterm`. The branch is `agent/petunia/uterm-001`.

## TL;DR

The run is in progress. See the run state below.

## Run state

- Code repo base commit for the run and for the row: `92da487` ("Schedule UTERM-001 M1-M9 as the first queue row")
- Specs commits: the specs live in the code repo, so the milestone commits are the specs commits

| Milestone | Run status | Commit |
|-----------|------------|--------|
| M1 App skeleton and theme tokens | DONE | see M1 |
| M2 Terminal applet in a single pane | QUEUED | |
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

Commit: see the next amendment. A report cannot hold the SHA of the commit that carries it.

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

## Status

In progress.

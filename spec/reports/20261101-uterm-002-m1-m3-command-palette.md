# UTERM-002 M1-M3: Command palette work-queue run

Started 2026-11-01. This report covers a `/work-queue next 2` run. Its first row is `UTERM-002 M1-M3`, the command
palette, at `spec/proposals/UTERM-002-command-palette.md`. Its second row is `UTERM-013 M1-M2`, shortcut ownership and
reopening closed tabs, reported in [20261101-uterm-013-m1-m2-shortcut-ownership-and-reopen.md](
20261101-uterm-013-m1-m2-shortcut-ownership-and-reopen.md). The specs live in the code repo, so every commit below is
in `/Users/ripta/projects/uniterm`, on `main`. Nothing is pushed.

## TL;DR

In progress.

## Run state

- Base commit for the run and for the first row: "Merge pull request #6 from
  space-armada/agent/petunia/finish-foundation-schedule-palette"
- Specs commits: the specs live in the code repo, so the milestone commits are the specs commits

| Milestone | Run status | Commit |
|-----------|------------|--------|
| UTERM-002 M1 Floating palette with commands | DONE | "Add a command registry and a floating command palette" |
| UTERM-002 M2 Tab search | IN PROGRESS | |
| UTERM-002 M3 Docked mode | QUEUED | |
| UTERM-002 row review | QUEUED | |
| UTERM-013 M1 Applet-declared shortcuts | QUEUED | |
| UTERM-013 M2 Reopen with Cmd-Shift-T | QUEUED | |
| UTERM-013 row review | QUEUED | |
| Final review | QUEUED | |

Held or blocked rows: none. UTERM-013's row depends on UTERM-002 M1, which this run builds first.

## Local checks

Every milestone runs `make fmt-check`, `make lint`, `make check`, `make test-package`, and `make test-app`. The UI
tests run outside the sandbox, since they drive the app through Launch Services and Accessibility. `make
ghostty-offline-check` runs once, at the final review, since no milestone touches `ghostty.pin`.

## Run-level best guesses

These come from the approved plan at `/Users/ripta/.claude/plans/spicy-weaving-fern.md`.

- UTERM-002's grace-tier lines are stale, since UTERM-001 M10 removed grace-tier panes. M2 amends them as a correction
  of fact.
- An unavailable command is shown disabled, not hidden. If wrong, the palette filters them out instead.
- The floating palette is an overlay view inside the window, not an `NSPanel`.
- The click that dismisses a palette is delivered normally to what it hits.
- When the palette and the status bar dock at the same edge, the status bar is outermost.
- The closed-tab list depth is 20, matching the pane undo depth.
- Ranking constants, debounce intervals, and overlay sizes are the implementer's, recorded in As built.
- UTERM-002 M1 leaves the Close Pane / Close Tab title switch alone. UTERM-013 M1 renames it to "Close".

## Milestones

### UTERM-002 M1: Floating palette with commands

Commit: "Add a command registry and a floating command palette". It also carries the `.cg.yaml` fix that points the
`proposals.py` allow rule at the current plugin version.

Checks, final round: `make fmt-check`, `make lint`, and `make check` pass. `make test-package` ran 437 tests, with 4
skipped and 0 failures. `make test-app` ran 59 UI tests, with 0 failures, in 437 seconds. `proposals.py check` and
`proposals.py freeze` report nothing.

Test cost: the new unit test files take about 0.9 seconds together. The 8 new UI tests in `CommandPaletteUITests` take
54 seconds.

Best guesses by the implementer:

- The registry lives in a `Commands` folder of WindowKit, not a new module.
- The palette-focused dispatch rules live in one dispatch point on the window controller, not in the key route. A
  menu item chosen with the mouse then gets the same rules, which an M1 check requires. "Command source" was amended
  for it, with a Decision Log entry. If wrong, the rules move into the key route, and mouse-chosen items lose them.
- Terminal text actions, such as text size and clear, reach the terminal through a new applet-contract protocol for
  text actions. WindowKit cannot import the terminal module.
- Palette sizes, match scoring, and the recency boost are recorded in the M1 As built block.
- Close is titled "Close Tab or Pane" in the palette. Select-tab-by-number and the palette toggle are not listed.
- Unavailable commands show disabled, and the arrow keys and Enter skip them. A pane-scoped command whose pane is gone
  counts as available, so choosing it posts a status message.
- A click outside the floating palette on something that takes no keyboard returns focus to the prior pane. M3
  states this for the docked palette. M1 applies it to floating too.
- The UI tests apply App Shortcuts remaps with the `-NSUserKeyEquivalents` launch argument.

Deviations and defects found along the way:

- Cmd-Z in the palette's field did nothing until the window routed undo through the field editor's undo manager.
- A second Cmd-Q cancelled the open quit question. Quit is now the app delegate's own item, disabled while the
  question is open.
- No UI test drives a sheet over a showing palette. A unit test covers the rule that hiding never takes focus back.

Review findings:

- Decision Log entry out of date order: fixed.
- Two comment-craft nits: fixed.
- The "Command source" marker date replaced the earlier one: dismissed, since `proposals.md` says a later revision
  replaces the marker.
- Unlisted commands, such as Cmd-1 to Cmd-9, filled the 8-deep recency list: traced and confirmed, then fixed with a
  test. Only commands listed in the palette count toward recency now.
- The key route missed menu items whose key differs from the typed character, such as Bigger Text on Cmd-+ and
  Dismiss Message on Delete: traced and confirmed, then fixed with tests. Cmd-} and Cmd-Shift-] are still not unified.
  UTERM-013 M1 owns that canonical form.

ADR review: no conflicts. Two uncovered decisions were raised, and neither is recorded as a candidate. The window key
route is mechanism that UTERM-013 keeps out of ADR-04 on purpose. A registry ADR was already declined on 2026-11-01.

## Status

In progress.

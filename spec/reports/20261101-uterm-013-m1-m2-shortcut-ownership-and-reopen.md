# UTERM-013 M1-M2: Shortcut ownership and reopen work-queue run

Started 2026-11-02. This report covers the second row of a `/work-queue next 2` run: `UTERM-013 M1-M2`, at
`spec/proposals/UTERM-013-shortcut-ownership-and-reopen.md`. UTERM-013 moves applet shortcuts to the applets, reserves
uniterm's window keys, and adds Cmd-Shift-T to reopen the newest closed tab or pane. The run state and the run-level
best guesses are in [20261101-uterm-002-m1-m3-command-palette.md](20261101-uterm-002-m1-m3-command-palette.md). The
specs live in the code repo, so every commit below is in `/Users/ripta/projects/uniterm`, on `main`.

## TL;DR

In progress.

## Row base

The row starts at "Finish the command palette", the commit that finished UTERM-002. UTERM-013's dependency on UTERM-002
M1 is met.

## Milestones

### UTERM-013 M1: Applet-declared shortcuts

Commit: "Let applets declare their own shortcuts and reserve uniterm's window keys".

Checks, final round: `make fmt-check`, `make lint`, and `make check` pass. `make test-package` ran 521 tests, with 4
skipped and 0 failures. `make test-app` passed in 565 seconds. `proposals.py check` and `proposals.py freeze` report
nothing.

Test cost: the new unit test files run in under a second together. `ShortcutOwnershipUITests` adds a few UI tests of a
few seconds each.

Best guesses by the implementer:

- Menu building moved from the App target into WindowKit. Menu items carry their command ID, so each command is now
  declared once, and the per-command adapters are gone. The hand-built menu file is deleted.
- Applets register a command set with IDs namespaced by applet type, such as `terminal.clear`. The terminal's old
  `uniterm.*` IDs for tabs, text size, and clear are retired, not reused. Recency is in memory only, so nothing stored
  names them.
- A command's action receives its applet at run time and keeps no reference to it.
- The reserved set is read from the live menu: every item that is not an applet's, plus the fixed Edit keys. That
  covers the keys AppKit adds itself without a table. The set is re-read at install, on a defaults change, on app
  activation, and before every routed Command-key press. The press-time read is the guarantee, since AppKit's timing
  for applying a remap is undocumented.
- The key route tries a remapped item first, then uniterm's items, then applet items. A disabled remapped or uniterm
  item consumes the key. A disabled applet item lets it fall through. Two remaps on one key resolve by menu-bar order.
- Cmd-1 to Cmd-9 still reach the launcher, because the terminal's tab items are hidden while a launcher has focus.
  The launcher's special first offer in the key route is gone.
- File > Close also closes a non-main key window such as Settings, and never a sheet. The Settings window's own close
  handler was removed.
- An agreed close of a running tab that has become the last tab answers "nothing to close", so the pane close guard
  asks again.
- The palette keeps "Close Tab or Pane" as its entry title. The menu item is "Close".

Amendments, each with a Decision Log entry giving the prior meaning: "What one shortcut declaration is", "Which keys
uniterm reserves", "Who decides what Cmd-W closes", the launcher's first offer of Cmd-1 to Cmd-9, and "What happens on a
key conflict".

Residuals: the test cannot assert that a closed pane's applet is freed, since the window keeps references for a while.
It pins that a command aimed at a closed pane reaches nothing. The Settings window has no editable text field, so the
check about Settings rows has nothing to act on. Cut is disabled in the terminal.

UTERM-002's As built describes the shapes M1 replaced, such as the text-action protocol and the launcher's first
offer. Those were true when UTERM-002 shipped, so they are not corrections of fact, and UTERM-002 stays frozen.

Review findings:

- ADR-04 says the user is told when an applet loses a key. A key dropped after the applet type's first warning was
  silent. The ADR review called this a plausible conflict, and the reviewer flagged the same gap. Fixed: each check of
  the reserved set posts at most one warning per applet type, naming only drops not announced before. "What happens on a
  key conflict" and two M1 checks were amended to match.
- The Decision Log entry gave only the new rules: fixed, one entry per amendment with its prior meaning.
- The edit-actions check was tested only on the launcher field: fixed with a menu test of the edit selectors.
- Two remaps on one key had no direct test: fixed with a unit test through a remap seam.
- A test polled with real sleeps: fixed with a direct signal from the test host.
- A doc comment sat on the wrong declaration: fixed.

ADR review: one plausible ADR-04 conflict, fixed as above. Its candidates are already settled. The namespaced command
ID candidate waits on UTERM-003, per the Decision Log. The key route is mechanism the proposal keeps out of ADR-04. The
title-as-remap-contract rule is a UTERM-002 risk that shapes only the menu.

## Status

In progress.

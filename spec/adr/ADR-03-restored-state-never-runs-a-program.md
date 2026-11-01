# ADR-03: Restored State Never Runs a Program Unasked

**Status:** accepted
**Date:** 2026-10-31

## Context

Every applet returns a restorable description of itself. Undo close uses it once the grace period ends. Layout
persistence uses it at every launch.

A terminal in program mode runs one given command. If its description were a launch recipe, then undo or relaunch would
run that command again. That command could be `./deploy.sh` or a database migration.

## Decision

A restorable description is inert state, never a launch recipe. Restoring an applet from its description never runs a
program the user did not ask to run at that moment.

- The rule belongs to the applet contract, so it holds for every applet's description.
- A terminal in program mode reopens showing its command and a Run action. It runs nothing until the user asks.
- A terminal in shell mode starts a fresh interactive shell. Starting a shell is not running the user's program.

## Rationale

Repeated execution is a correctness failure. It can deploy twice, migrate twice, or send twice. Undo and relaunch are
meant to be safe. A user presses Cmd-Z to get a layout back, not to repeat a side effect.

Making the description inert closes this hole for every applet at once. Guarding each restore path one by one would
leave holes.

## Consequences

- A restored program-mode pane needs one extra action to run its command.
- The same description serves undo and relaunch, so neither path can re-run a program on its own.

## Alternatives Considered

- **A description that is a launch recipe.** That is the simplest restore. Relaunching program mode as it was re-runs
  its side effects.

## References

- UTERM-001: "What undo close restores" and "What layout persistence restores, and in what format"

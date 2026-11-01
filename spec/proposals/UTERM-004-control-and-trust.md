# UTERM-004: Pane Control and Trust

**Status:** draft
**Created:** 2026-10-31
**Updated:** 2026-10-31

## Dependencies

- UTERM-001
- UTERM-003

## Impacts

- UTERM-005, UTERM-006, UTERM-007, UTERM-008, UTERM-009, UTERM-010 — "Control levels": each applet declares which
  levels it supports
- UTERM-001 — "What layout persistence restores": saved layouts may need to record control levels

## Summary

Programs and scripts can drive panes. This proposal defines who may control which pane, and how. It covers three
control levels: remote-controlled, disconnected, and exec. It also lets a program request a layout for the panes it
owns.

## Motivation

The write-up's best ideas need panes that talk to each other. One example is telling the nearest browser pane to open a
page. Another is a presentation program showing slides, notes, and charts in separate panes. Each needs rules, so that
one program cannot take over panes it has no business touching.

## Design Decisions (Settled)

### Control levels

- **Remote-controlled (CONTROL-1).** Other programs may drive the pane, within the trust rules. The pane shows a visible
  marker, such as a robot icon.
- **Disconnected (CONTROL-2).** Nothing can talk to the applet once it runs. The user can still close the pane.
- **Exec (CONTROL-3).** The pane runs a program and connects it to the applet. User events go to the program's stdin.
  The program's stdout drives the applet. Its stderr goes to the status bar.

Each applet declares which levels it supports.

### Trust follows the pane tree

A program in a pane is trusted with that pane and the panes beneath it in the tree. It is not trusted with panes above
it or beside it.

Rationale: the write-up's presentation example. The program owns its subtree and may lay it out.

### Same window only

A program may control panes only in its own window.

### Layout requests

A trusted program may request a layout for its own subtree. For example, it may ask for three panes holding a slide, a
set of notes, and a chart.

## Design Decisions (Open)

### How uniterm knows which pane a program runs in

Options:

- **An environment variable** set in each terminal tab, such as a pane token. Easy, but any child process inherits it
  and can leak it.
- **Process ancestry.** The app maps the caller's process to a tab's process tree. Harder to fake. More work.
- **A per-tab socket or file descriptor** passed to the shell. Only processes holding it can connect.

### "Nearest" pane

- How "the nearest browser pane" is defined: closest in the tree, most recently focused, or explicit.
- What happens when no such pane exists: fail, or open one.

### Exec wire format

- The message format on stdin and stdout, such as JSON lines.
- How each applet documents its events and commands.

### Is exec a control level?

The write-up notes that exec might be a separate dimension from control. Options: one level among three, or a separate
setting that combines with the others.

### Saved layouts

- How a program's requested layout is remembered and restored.
- Whether a restored layout keeps its trust, or asks again.

## Risks

- **A process gains control of panes it should not** — likelihood: medium, impact: high.
  Mitigation: deny by default. Mark controlled panes visibly. Scope trust to the caller's subtree and window. Test
  denied cases.
- **The exec wire format becomes a contract external programs depend on** — likelihood: high, impact: medium.
  Mitigation: version the format from its first release.
- **Trust rules are too strict to be useful** — likelihood: medium, impact: medium.
  Mitigation: build the presentation example as a test case in M4 and adjust before acceptance.

## Milestones

### M1: Caller identity

**Status:** NOT STARTED

- uniterm identifies which window and pane a calling program runs in
- A call from outside any uniterm pane is rejected unless the user allows it

### M2: Remote-controlled and disconnected panes

**Status:** NOT STARTED

- A remote-controlled pane shows a visible marker
- A disconnected pane rejects every control call
- A program cannot control a pane above or beside its own

### M3: Exec panes

**Status:** NOT STARTED

- An exec pane starts a program and sends applet events to its stdin
- The program's stdout drives the applet
- The program's stderr appears in the status bar

### M4: Layout requests

**Status:** NOT STARTED

- A program can request a layout for its own subtree
- A request for panes outside its subtree is refused
- The presentation example works end to end with slides, notes, and a chart in separate panes

## Decision Log

- 2026-10-31: Drafted from the original write-up without an interview. The open questions hold everything undecided.

## References

- Original write-up: `~/projects/private_specs/uniterm/spec/research/original-writeup.md`, CONTROL-1 to CONTROL-3 and groups

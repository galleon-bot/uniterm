# UTERM-012: Shell Blocks

**Status:** deferred
**Created:** 2026-10-31
**Updated:** 2026-10-31
**Revisit:** when UTERM-001 M5 is DONE and the behavior for full-screen programs is sketched

## Dependencies

- UTERM-001

## Summary

The terminal applet groups each shell command into a block. A block holds the command, its output, and its exit code. A
block can collapse to show only the command and exit code. The command, stdout, and stderr can be copied separately.

## Motivation

Scrollback mixes many commands into one stream. Blocks make each command's output easy to find, fold away, and copy.

## Design Decisions (Settled)

### One command is one block

A block runs from the start of one command to its end.

### Collapse and expand

A collapsed block shows the command and maybe its exit code. An expanded block shows everything, like a normal
terminal.

### Deferred

The write-up has not settled how blocks treat programs that clear the screen or draw full-screen. This proposal waits
for that.

## Design Decisions (Open)

### Finding block boundaries

Options:

- **Shell integration escape sequences,** such as OSC 133 prompt marks. Ghostty already supports these.
- **A uniterm-specific shell hook.**

### Separating stdout and stderr

A terminal sees one merged stream. Separating them needs shell cooperation, such as redirecting stderr through a second
channel. Decide whether this is worth it.

### Full-screen and screen-clearing programs

How a block treats `vim`, `less`, `top`, or `clear`.

### Customization

The write-up wants block behavior to be customizable later. Decide what is configurable.

## Risks

None identified. The proposal is deferred and commits to nothing yet.

## Milestones

### M1: Collapsible blocks

**Status:** NOT STARTED

- Each command in a shell tab becomes a block
- A block collapses to its command and exit code, and expands again
- A block's command and output can each be copied

## Decision Log

- 2026-10-31: Deferred. The write-up calls blocks pie-in-the-sky until full-screen program behavior is worked out.
  Revisit when UTERM-001 M5 is done and that behavior is sketched.

## References

- Original write-up: `~/projects/private_specs/uniterm/spec/research/original-writeup.md`, APPLET-1

# UTERM-014: Palette and Reopen Review Fixes

**Status:** implemented
**Created:** 2026-11-02
**Updated:** 2026-11-02

## Dependencies

- UTERM-002
- UTERM-013

## Impacts

- UTERM-001 — "A pane whose applet exited on its own" adds no undo entry. This proposal reverses that rule.
- UTERM-002 — "Hotkey default", "Hotkey configurability", and the docked strip's place below the title bar.
- UTERM-013 — the exited-tab rule in M2, and the terminal's Clear Screen key in M1.

## Summary

The user's hands-on review of UTERM-002 and UTERM-013 found that the palette opened on the wrong key, a top-docked
palette sat below the title bar, the palette's field and results were misshapen, and a tab or pane whose shell exited
could not be reopened. This proposal records the user's decisions and the fixes.

## Motivation

The user had asked for Cmd-K as the palette key. That request never reached UTERM-002. The draft came from the original
write-up, which says only "hotkey", and an autonomous review pass chose Cmd-Shift-P. The palette is meant to be opened
all the time, so its key should be a single chord.

The write-up asks for content that extends up to the title bar. A top-docked palette below the title bar cost the panes a
row and left a gap above the field.

A close is a close, however it happens. Typing `exit` closes a tab as surely as Cmd-W does, so Cmd-Shift-T must bring it
back.

## Design Decisions (Settled)

### Cmd-K opens the palette

Cmd-K activates the palette in both modes, as one toggle. It is a reserved window key, so it works in every applet. The
menu item keeps its fixed title, "Show Command Palette", so App Shortcuts remaps keep matching.

The terminal's Clear Screen has no default key. It stays in the palette and in the terminal's menu, and a user can give
it a key through App Shortcuts.

### A top-docked palette sits in the title bar row

A palette docked at the top sits in the title bar row, centered, and flush with the window's top edge. It keeps 84 points
from each side of the window, so it clears the traffic lights. The rest of the row still drags the window. The pane area
keeps the whole safe area. A palette docked at the bottom keeps its strip.

### The field and results are sized for their place

The field's text centers in its box at any box height. A floating field is 40 points tall. A bottom-docked field is 24
points tall in a 32-point strip. A title-bar field is 22 points tall. The results panel has 6 points of padding on every
side, and its rows line up with the field's text.

### Every close is reopenable

A tab whose shell exits goes on the applet's closed-tab list, as a Cmd-W close does. A pane whose applet ends goes on the
window's reopen list, and closes without a question. A launcher still has nothing to reopen. Reopening follows ADR-03: a
reopened shell is a fresh shell, and a program-mode pane shows its command with a Run action.

## Design Decisions (Open)

None.

## Risks

- **A user's Cmd-K habit from Terminal.app clears nothing** — likelihood: medium, impact: low.
  Accepted: the user chose Cmd-K for the palette, and Clear Screen is one palette search away.

## Milestones

### M1: Review fixes

**Status:** DONE

- Cmd-K shows and hides the palette with a terminal focused. Cmd-Shift-P does nothing
- Clear Screen has no key equivalent and still runs from the palette
- A top-docked palette's strip spans the title bar row, and the pane area's top is the safe area's top
- The field's text is vertically centered in floating, bottom-docked, and title-bar placements
- The results panel's first row starts 6 points below its top border
- A tab whose shell exits, and a pane whose shell exits, both come back with Cmd-Shift-T

**As built:**

- The results of a title-bar palette start at the pane area's top edge, 1 point further from the field than the usual
  4-point gap, so they never cover the title bar.

## Decision Log

- 2026-11-02: Cmd-K opens the palette, at the user's direct request. The autonomous choice of Cmd-Shift-P in UTERM-002 is
  superseded. Clear Screen loses its Cmd-K default and gets no other key.
- 2026-11-02: A top-docked palette sits in the title bar row, flush with the window's top edge.
- 2026-11-02: Every close is reopenable, including a shell that exits on its own. UTERM-001's no-entry rule for exited
  panes and UTERM-013's for exited tabs are superseded.
- 2026-11-02: Field heights of 40, 24, and 22 points and 6 points of results padding. Chosen by the agent from
  the review screenshots. (agent choice)

## References

- ADR-03: a reopened pane never runs a program unasked
- ADR-04: uniterm owns key bindings

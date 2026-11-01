# UTERM-002: Command Palette

**Status:** draft
**Created:** 2026-10-31
**Updated:** 2026-10-31

## Dependencies

- UTERM-001

## Impacts

- UTERM-003 — "Applets publish their tabs": the scripting API may expose the same entries

## Summary

Each window gets a command palette region. The palette can float or dock. It finds and jumps to any tab of any applet
in the window, and runs commands.

## Motivation

A window can hold many panes, and each applet can hold many tabs. Finding one by eye gets slow. A palette gives one
keyboard path to every tab and every command.

## Design Decisions (Settled)

### The palette is a region

The palette is a region, as defined in UTERM-001. Its role is fixed. Its mode and position are settings.

### Two modes

- **Floating.** Hidden by default. A hotkey shows it over the window. It takes focus while shown.
- **Docked.** Always visible at the top or the bottom of the window. It does not take focus until the hotkey activates
  it.

### Applets publish their tabs

Applets make their tabs findable in the palette. Choosing an entry focuses that pane and switches to that tab. When a
tab closes, its entry disappears.

### Commands

The palette also runs commands, such as split pane, close pane, and new window. Commands and tabs share one search.

## Design Decisions (Open)

### How applets publish tabs

Options:

- **Register and unregister calls.** An applet calls the palette when a tab opens or closes. Simple, but an applet can
  forget to unregister.
- **The palette queries applets.** Each applet exposes its current tabs. The palette asks when it opens. Nothing can go
  stale.
- **An observable model.** Each applet's tab list is observable. The palette subscribes.

### Search scope

- Whether the palette searches only the current window, or every window.
- How results rank: fuzzy match, recency, or both.

### Command source

- Whether commands are declared in Swift only, or also in Janet once UTERM-003 lands.
- Whether the palette should eventually call the Janet API for every command. The write-up suggests it might.

### Hotkey

- The default hotkey for each mode.
- Whether the hotkey is configurable in this proposal.

## Risks

- **A global hotkey collides with a shortcut in a terminal program** — likelihood: high, impact: medium.
  Mitigation: the hotkey is a window-level shortcut, not a system-wide one. A later setting lets the user change it.
- **Stale tab entries after an applet crashes** — likelihood: medium, impact: low.
  Mitigation: settled by the publishing option chosen. A query model removes this risk.

## Milestones

### M1: Floating palette with commands

**Status:** NOT STARTED

- A hotkey shows and hides a floating palette over the focused window
- Typing filters a list of built-in commands, and Enter runs the selected one
- Escape hides the palette and returns focus to the pane that had it

### M2: Tab search

**Status:** NOT STARTED

- Every terminal tab in the window appears in the palette
- Choosing a tab focuses its pane and switches to that tab
- A closed tab no longer appears

### M3: Docked mode

**Status:** NOT STARTED

- The palette docks at the top or the bottom of the window
- A docked palette does not take focus until the hotkey activates it
- Switching between floating and docked keeps search behavior the same

## Decision Log

- 2026-10-31: Drafted from the original write-up without an interview. The open questions hold everything undecided.

## References

- Original write-up: `~/projects/private_specs/uniterm/spec/research/original-writeup.md`

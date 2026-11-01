# UTERM-013: Shortcut Ownership and Reopening Closed Tabs

**Status:** draft
**Created:** 2026-11-01
**Updated:** 2026-11-01

## Dependencies

- UTERM-001

## Impacts

- UTERM-001 — "Whether uniterm reads the user's Ghostty config": every binding is a uniterm menu item today. This
  proposal moves applet actions to the applet.
- UTERM-002 — "Hotkey": the palette's key is a window-level key, so no applet may claim it
- UTERM-005 through UTERM-010 — "The applet contract": each applet declares its own key bindings and menu items

## Summary

uniterm binds only window-level shortcuts. Each applet declares the shortcuts for its own actions, such as tabs,
copy and paste, text size, and clearing. Cmd-Shift-T reopens what was closed most recently: a tab in the focused pane
when it has one, and otherwise the last closed pane. Cmd-Z goes back to undoing text edits only.

## Motivation

The user walked through the built app and found three problems.

- Cmd-Z for reopening a pane feels wrong. Browsers and editors use Cmd-Shift-T to reopen what was just closed.
- A closed terminal tab cannot be reopened. Applets own their tabs, so they should own reopening them too.
- uniterm binds terminal-only actions, such as Clear Screen on Cmd-K, as window shortcuts. Those belong to the
  terminal. uniterm should bind only what works across applets. That also keeps keys like Cmd-K free for later
  window-level features, such as the palette.

## Design Decisions (Settled)

### uniterm binds window-level shortcuts, and applets bind their own

uniterm binds the shortcuts that act on the app, a window, or the pane tree. They include settings, hide and quit, a
new window, splits, closing a pane, pane focus, the message history, and reopening. Each applet declares the
shortcuts for its own actions. The terminal declares new tab, tab selection, copy, paste, select all, text size, and
clear.

uniterm still clears libghostty's built-in bindings, as ADR-04 requires, so no key reaches libghostty's own handling.

Chosen by the user on 2026-11-01.

### Applets own their tabs, and reopening them

An applet with tabs keeps its own list of closed tabs, as descriptions. uniterm only asks the focused applet to reopen
one.

Chosen by the user on 2026-11-01.

### Cmd-Shift-T reopens, and Cmd-Z undoes text edits only

Cmd-Shift-T reopens the most recently closed tab in the focused pane when that pane has one. Otherwise it reopens the
last closed pane. Cmd-Z undoes edits in a focused text field and nothing else.

Chosen by the user on 2026-11-01.

## Design Decisions (Open)

### How an applet declares its shortcuts

- Menu items in an applet menu that appears while the applet has focus, or items merged into the standard menus.
- Whether a declaration is a key plus a selector, or a richer command that the palette can also list (UTERM-002).

### Conflicts between uniterm and an applet

- Which keys uniterm reserves, so no applet can claim them. The palette's key is one.
- What happens when an applet declares a reserved key: a load error, a warning, or a silent loss.

### Close keys

- Cmd-W closes a tab first, then the pane at the last tab. Decide whether the applet or uniterm owns that choice.

### Reopening

- How long an applet's closed-tab list is, and whether it survives a relaunch in the applet's description.
- Whether Cmd-Shift-T in a pane with no closed tabs falls through to reopening a pane, or does nothing.
- A closed tab running something: the tab-close guard already asks. Decide whether the reopen restores the tab's
  working directory the same way a pane reopen does.

### ADR-04

ADR-04 says "Every binding is uniterm's own". Its purpose was to keep libghostty's built-in bindings out. This
proposal keeps that purpose, but moves applet bindings to the applet. Decide how ADR-04 changes.

## Risks

- **An applet's key shadows a window shortcut** — likelihood: medium, impact: medium.
  Mitigation: settled by the conflict rule. A reserved set keeps window keys working in every applet.
- **Users with Cmd-Z habits lose pane undo** — likelihood: low, impact: low.
  Mitigation: Cmd-Shift-T is the common reopen key in browsers and editors.

## Milestones

### M1: Applet-declared shortcuts

**Status:** NOT STARTED

- An applet declares its shortcuts, and they work only while that applet has focus
- A reserved window shortcut works in every applet, and an applet cannot claim it
- The terminal's tab, copy, paste, select all, text size, and clear shortcuts come from the terminal, not uniterm

### M2: Reopen with Cmd-Shift-T

**Status:** NOT STARTED

- Closing a terminal tab keeps its description in the terminal's closed-tab list
- Cmd-Shift-T reopens the most recently closed tab in the focused pane, in the same working directory rule as a pane
- With no closed tab in the focused pane, Cmd-Shift-T reopens the last closed pane
- Cmd-Z undoes a text edit in a focused text field, and does nothing to panes

## Decision Log

- 2026-11-01: Drafted from the user's walkthrough of the built app, feedback F1 to F3. The three settled decisions
  are the user's.

## References

- UTERM-001: "Whether uniterm reads the user's Ghostty config" and "What undo close restores"
- ADR-04
- ADR-05

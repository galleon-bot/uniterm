# ADR-04: uniterm Owns Its Key Bindings and Terminal Config

**Status:** accepted
**Date:** 2026-10-31

## Context

libghostty builds its surface from a config object. Ghostty's own app loads the user's Ghostty config files. That
config can set the theme, palette, and colors, and also `term`, `shell-integration`, `command`, and
`working-directory`. Each of those can break a uniterm decision.

libghostty also binds keys by default, even with no config file loaded. Cmd-Z, Cmd-W, Cmd-T, Cmd-D, and Cmd-Q are among
them. A focused terminal surface would catch those keys before uniterm sees them. That would break undo close, pane
close, and the later command palette hotkey.

Inside uniterm, keys have two owners. Window keys act on the app, a window, or the pane tree, and must work whatever
applet has focus. Applet keys act on one applet's content, such as a terminal's tabs, text size, or clear. AppKit asks
the focused view before the menu, so an applet view, or web content inside one, could otherwise take a window key.

## Decision

uniterm alone owns its key bindings and its terminal configuration. No other app's config applies.

- uniterm does not load the user's Ghostty config files, or any file in Ghostty's syntax that the user edits.
- uniterm clears libghostty's built-in key bindings. No key comes from libghostty or from Ghostty's config.
- Window keys reach uniterm in every applet. No applet, no view inside one, and no content it hosts can take them.
- An applet binds keys only for its own actions, and only keys uniterm does not reserve. Terminal actions, such as font
  zoom and clear, are the terminal applet's, and call into the surface through the terminal surface protocol.
- A user's own remap of a menu item wins over every default key, uniterm's or an applet's.
- uniterm generates the config it hands libghostty from its own settings and theme tokens.

## Rationale

With one owner of the config, every settled decision holds by construction. A deny list over an external config can
never be complete, since each new Ghostty key is allowed by default. Sharing Ghostty.app's file would also tie uniterm
to an app that upgrades on its own schedule.

Window keys must mean the same thing in every pane, or Cmd-W and the palette key stop being dependable. Only the applet
knows its own actions, so it owns their keys, and uniterm's menu stays limited to what works across applets. Without
the rule, a later applet would either put its keys back in uniterm's menu or let its hosted content take a window key.

## Consequences

- A Ghostty option uniterm does not expose is out of reach until it becomes a uniterm setting. Adding such settings,
  such as fonts, leaves this decision unchanged.
- The generated config must escape or reject every value, so a setting cannot inject a config line.
- uniterm keeps a reserved set of window keys. A new window key can take a key an applet already uses. The applet then loses that key, and the user is told.
- A new applet declares its own keys. It never adds them to uniterm's window keys.

## Alternatives Considered

- **Read Ghostty's own config, then force uniterm's values.** Its deny list misses keys that break settled decisions,
  and it adds skew against Ghostty.app.
- **Read a uniterm-owned file in Ghostty syntax.** It has the same deny-list gap. It also gives terminal options a
  second source of truth beside uniterm's settings.

## References

- UTERM-001: "Whether uniterm reads the user's Ghostty config" and "Where settings live"
- UTERM-002: "Hotkey default"
- UTERM-013: "uniterm binds window-level shortcuts, and applets bind their own" and "Which keys uniterm reserves"
- ADR-01

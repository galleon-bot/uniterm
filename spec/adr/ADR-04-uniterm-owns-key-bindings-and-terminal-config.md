# ADR-04: uniterm Owns Every Key Binding and Its Terminal Config

**Status:** accepted
**Date:** 2026-10-31

## Context

libghostty builds its surface from a config object. Ghostty's own app loads the user's Ghostty config files. That
config can set the theme, palette, and colors, and also `term`, `shell-integration`, `command`, and
`working-directory`. Each of those can break a uniterm decision.

libghostty also binds keys by default, even with no config file loaded. Cmd-Z, Cmd-W, Cmd-T, Cmd-D, and Cmd-Q are among
them. A focused terminal surface would catch those keys before uniterm sees them. That would break undo close, pane
close, and the later command palette hotkey.

## Decision

uniterm alone owns its key bindings and its terminal configuration. No other app's config applies.

- uniterm does not load the user's Ghostty config files, or any file in Ghostty's syntax that the user edits.
- uniterm clears libghostty's built-in key bindings. Every binding is uniterm's own. Terminal-local actions, such as
  copy, paste, and font zoom, are uniterm bindings that call into the surface through the terminal surface protocol.
- uniterm generates the config it hands libghostty from its own settings and theme tokens.

## Rationale

With one owner, every settled decision holds by construction. A deny list over an external config can never be
complete, since each new Ghostty key is allowed by default. Sharing Ghostty.app's file would also tie uniterm to an app
that upgrades on its own schedule.

## Consequences

- A Ghostty option uniterm does not expose is out of reach until it becomes a uniterm setting. Adding such settings,
  such as fonts, leaves this decision unchanged.
- The generated config must escape or reject every value, so a setting cannot inject a config line.

## Alternatives Considered

- **Read Ghostty's own config, then force uniterm's values.** Its deny list misses keys that break settled decisions,
  and it adds skew against Ghostty.app.
- **Read a uniterm-owned file in Ghostty syntax.** It has the same deny-list gap. It also gives terminal options a
  second source of truth beside uniterm's settings.

## References

- UTERM-001: "Whether uniterm reads the user's Ghostty config" and "Where settings live"
- UTERM-002: "Hotkey"
- ADR-01

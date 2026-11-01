# ADR-01: libghostty Is Reached Only Through the Terminal Surface Protocol

**Status:** accepted
**Date:** 2026-10-31

## Context

uniterm's terminal applet uses libghostty. Its embedder API, `ghostty.h`, is not stable. It calls itself Ghostty's
internal embedder API, built for Ghostty's own macOS app. It points external embedders to libghostty-vt instead.

libghostty's surface spawns the child process and owns the pty. The embedder sends input events and receives actions
through callbacks. It never sees raw VT bytes.

Later work reaches the terminal too. The palette, Janet scripts, control and trust, and shell blocks all do.

## Decision

Only one module talks to libghostty: the terminal surface module. No libghostty type appears outside it. UTERM-001 M2
holds the checks that enforce this.

Everything else talks to the terminal through uniterm's own terminal surface protocol. The protocol sits at the
terminal-session level. It covers spawn, input, resize, terminal actions, appearance updates, focus, the hosted view,
and the running-state query. It also carries events for title, working directory, prompt marks, notifications,
clipboard requests, and exit. It never sits at the VT level.

## Rationale

The boundary limits libghostty's churn to one module. Each upgrade touches that module and nothing else.

A session-level protocol is the only level libghostty can host, since libghostty owns the pty. It is also the level
SwiftTerm's process view works at. So SwiftTerm, or Ghostty's first-party Swift package once it ships, can replace
libghostty in one module.

## Consequences

- Each new terminal capability needs a protocol addition before a caller can use it. A caller never reaches past the
  protocol for a shortcut.
- The protocol is internal, not published. It can change in step with its callers.
- A VT-level backend, such as libghostty-vt with uniterm's own pty, would need its own session layer beneath the
  protocol.

## Alternatives Considered

- **Use GhosttyKit directly wherever needed.** Every libghostty upgrade would then ripple through the app, and no
  fallback would be possible.
- **A VT-level protocol.** It cannot host libghostty's surface, which owns the pty.

## References

- UTERM-001: "Terminal surface behind an internal protocol" and "How to get libghostty"

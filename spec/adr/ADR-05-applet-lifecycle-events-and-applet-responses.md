# ADR-05: uniterm Owns the Applet Lifecycle Events, and Each Applet Owns Its Response

**Status:** accepted
**Date:** 2026-11-01

## Context

Each pane runs one applet. uniterm decides when an applet starts, when it leaves the screen, when it comes back, and
when it ends. Only the applet knows what those moments mean for its own content. A terminal, a browser, and a media
viewer each have different work in flight.

Undo close reopens a pane in the same place with the same applet. It is not a snapshot of a running process. An applet
that wants an undo to bring back more than its description can carry is free to do so. That is its own concern.

## Decision

uniterm defines the applet lifecycle and sends its events. Each applet decides how it responds.

- The events are start, detach, reattach, and close. Detach means the applet has left the screen and stays alive.
  Reattach means it is back. Close means the host is done with it.
- uniterm sends each event when it happens, and does nothing else on the applet's behalf. It never keeps an applet
  alive after closing it, and it never stops or signals the applet's work itself.
- On detach, an applet stops at once what the user would notice but cannot see. It pauses audio and video, and it
  holds back alerts.
- What an applet does after close is its own choice. It may end at once, finish its work after a delay, or save more
  state into its description. Any work it keeps alive after close must be bounded in time and visible to the user.
- Undo reopens a closed pane from its description, in the same place, with the same applet type.

## Rationale

The applet is the only part that knows what its work is, so it is the only part that can stop it correctly. A host that
reaches into an applet's work, such as by signalling a terminal's processes, has to understand every applet's
internals and still gets edge cases wrong.

A host that keeps closed applets alive makes every applet pay for a feature that only some want. It also makes the host
responsible for work it cannot see.

## Consequences

- Each applet defines what pausing means for it. An applet with nothing perceptible to pause has nothing to do on
  detach.
- An undo restores what the applet's description carries, and no more. A terminal's undo gives a fresh shell in the
  same directory.
- Since undo cannot restore a running session on its own, a close that would end running work asks the user first.
- An applet that keeps work alive after close owns its bound and its indicator.

## Alternatives Considered

- **The host keeps closed applets alive for a grace period.** This gives an exact undo, but the host must keep every
  applet quiet and bounded without understanding it. For a terminal, that means stopping its processes with signals.
- **The host defines events only, with no duties for applets.** This is simpler, but nothing would stop an applet from
  playing audio from a pane the user cannot see.

## References

- UTERM-001: "What undo close restores" and "Guarding a close that would kill running processes"
- ADR-03

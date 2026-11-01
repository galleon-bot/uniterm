# ADR-05: Detached Applets Go Quiet, and Their Background Life Is Bounded and Visible

**Status:** accepted
**Date:** 2026-11-01

## Context

An applet's lifecycle is its own. It is related to the display, but not tied to it. The host can take an applet off
screen and keep it alive. Undo close does this today. It keeps a closed pane's applet alive for a grace period, so an
undo brings back the exact session.

An applet that is alive but off screen can still act. It can play audio or video, raise alerts, or keep a program
running. The user cannot see the applet, so nothing on screen explains that activity.

## Decision

Detaching takes an applet off screen and keeps it alive. Every applet must behave correctly while detached.

- On detach, an applet at once stops what the user would notice but cannot see. It pauses audio and video playback,
  and it holds back alerts.
- A detached applet never runs unnoticed or without a bound. Work it keeps alive is limited to a bounded time, and the
  host shows a visible indicator for as long as any detached applet is alive. When the bound runs out, the host closes
  the applet.
- The user can end every detached applet at once from that indicator.
- Reattaching resumes what detaching paused, where the applet can.
- The rule covers every way the host detaches an applet, not only undo close.
- A detached pane still exists. It keeps its stable ID while detached, per ADR-02.

## Rationale

A user who closes a pane expects it to go quiet. Audio from a pane the user cannot find is confusing, and the user
cannot stop it.

Keeping the session alive is what makes an exact undo possible. That is worth keeping, as long as the cost is bounded
in time and the user can see it.

## Consequences

- Each applet defines what pausing means for it. An applet with nothing perceptible to pause has nothing to do on
  detach.
- Work that an applet cannot pause without losing it may continue, but only within the bound and under the indicator.
- Every new host path that detaches an applet needs a bound and an indicator before it ships.
- Closing a window or quitting must account for detached applets as well as visible ones.

## Alternatives Considered

- **Tear the applet down at close.** Nothing runs in the background, but undo can no longer restore the exact session,
  such as an unsaved editor buffer.
- **Keep detached applets running unchanged.** This is the simplest, but media plays from nowhere and work runs with no
  visible sign.
- **Tie the lifecycle to the view's visibility.** An applet can be off screen for reasons other than a close, so a
  visibility rule would pause or end applets the user still holds.

## References

- UTERM-001: "What undo close restores" and "Guarding a close that would kill running processes"
- ADR-02

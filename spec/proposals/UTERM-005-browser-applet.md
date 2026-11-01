# UTERM-005: Browser Applet

**Status:** draft
**Created:** 2026-10-31
**Updated:** 2026-11-01

## Dependencies

- UTERM-001

## Summary

A browser applet built on the system's WebKit. It has tabs, back, forward, and reload buttons, and an address bar with a
security indicator.

## Motivation

Docs, dashboards, and local dev servers often sit beside a terminal. A browser pane keeps them in the same window. It is
also the main target for remote control in UTERM-004, such as opening a page from a script.

## Design Decisions (Settled)

### WebKit

The applet uses `WKWebView`. It bundles no browser engine of its own.

### Controls

- Back, forward, and reload buttons.
- An address bar. Typed addresses without a scheme default to HTTPS.
- A security indicator. A page that is not fully secure shows a warning icon.

### Tabs

The applet supports multiple tabs. Its tab bar follows the same rule as the terminal applet: hidden when there is only
one tab.

## Design Decisions (Open)

### Address bar input

- Whether non-URL input runs a search, and with which engine.
- Whether `localhost` and plain IP addresses default to HTTP instead of HTTPS.

### Website data

- Whether all browser panes share one cookie and storage store, or each pane gets its own.
- Whether data persists across launches.

### Downloads, pop-ups, and new windows

- What a link that opens a new window does: a new tab, a new pane, or blocked.
- Where downloads go, and how the user sees them.

### Control levels

Which UTERM-004 levels the browser supports, and which commands it accepts, such as navigate and reload.

### The applet contract

Context from UTERM-001, which shipped the applet contract. ADR-05 and ADR-06 cover its lifecycle and its description
versioning. An ADR for the rest of the contract is a candidate in UTERM-001's Decision Log. This proposal may reshape
it, so it is not written yet. Every applet implements:

- A view the pane hosts, a title, and status bar segments.
- `start`, `close`, `focus`, and a palette update.
- `detach` and `reattach`. A closed pane's applet is hidden and kept alive for 10 seconds, so undo can bring back the
  exact session. ADR-05 says a detached applet goes quiet at once, pausing audio, video, and alerts. Any work it keeps
  alive is bounded in time and shown by a visible indicator.
- `isRunningSomething` and `runningLabels`. Closing a window or quitting asks first when any visible or hidden pane is
  running something, and the dialog names it.
- `describe()`, an inert description with a type and a per-type version. Undo past the grace period and layout restore
  both rebuild the applet from it. ADR-03 says restoring it never runs a program the user did not ask for. ADR-06 says
  the applet owns its payload and its version. It upgrades its own older versions, and bumps the version on any
  change an older build cannot round-trip. A description this build cannot read is kept byte-for-byte.

For the browser: a description likely holds each tab's URL. Restoring it loads pages, and a page can run scripts.
Decide whether that counts as running a program under ADR-03, or whether restore shows the URL and loads it only on
request. Also decide what counts as running something, such as a download or a form with unsent input. A detached
page keeps running during the grace period, audio included.

## Risks

- **Web content is untrusted input inside the app** — likelihood: high, impact: medium.
  Mitigation: WebKit runs content out of process. Expose no native bridge to page scripts in this proposal.
- **A shared website data store leaks sessions between panes** — likelihood: medium, impact: low.
  Mitigation: settled by the website data decision above.

## Milestones

### M1: Single-page browser

**Status:** NOT STARTED

- A pane can run the browser applet and load a typed address
- Back, forward, and reload work
- An address typed without a scheme loads over HTTPS

### M2: Security indicator

**Status:** NOT STARTED

- A page with any insecure content shows a warning icon in the address bar
- A fully secure page shows no warning

### M3: Tabs

**Status:** NOT STARTED

- The browser opens, switches, and closes tabs
- The tab bar is hidden when only one tab is open

## Decision Log

- 2026-10-31: Drafted from the original write-up without an interview. The open questions hold everything undecided.
- 2026-11-01: Added "The applet contract" with context from UTERM-001's implementation.

## References

- Original write-up: `~/projects/private_specs/uniterm/spec/research/original-writeup.md`, APPLET-3

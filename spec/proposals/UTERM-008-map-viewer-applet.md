# UTERM-008: Map Viewer Applet

**Status:** draft
**Created:** 2026-10-31
**Updated:** 2026-11-01

## Dependencies

- UTERM-001

## Impacts

- UTERM-004 — "Exec panes": the map is the write-up's example of an exec pane

## Summary

A map viewer applet built on MapKit. It shows a map with custom points of interest.

## Motivation

Location data from scripts and logs is easier to read on a map. The write-up also uses the map as its main example of an
exec pane. A program places pins, and the user's clicks go back to the program.

## Design Decisions (Settled)

### MapKit

The applet uses MapKit's map view. Apple Maps data is available to apps this way.

### Points of interest

The applet shows custom pins, each with a coordinate and a label.

## Design Decisions (Open)

### Where pins come from

Options:

- **A file,** such as GeoJSON.
- **A script,** through the UTERM-003 host API.
- **An exec program,** through UTERM-004. Clicks go to the program as JSON. The program adds and removes pins through its
  output.

### Map styles

Standard, satellite, hybrid, and whether a dark map follows the dark theme.

### Pin styling

Colors, icons, and grouping of nearby pins.

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

For the map viewer: a description likely holds the visible region and where the pins came from. When pins came from a
program's output, restoring must not run that program again.

## Risks

- **MapKit needs network access and may need an entitlement** — likelihood: medium, impact: low.
  Mitigation: confirm the entitlements in M1. Show a clear message when the map cannot load.

## Milestones

### M1: Basic map

**Status:** NOT STARTED

- A pane can run the map applet and show a map
- The user can pan and zoom

### M2: Custom pins

**Status:** NOT STARTED

- The applet shows pins from the chosen pin source
- Selecting a pin shows its label

## Decision Log

- 2026-10-31: Drafted from the original write-up without an interview. The open questions hold everything undecided.
- 2026-11-01: Added "The applet contract" with context from UTERM-001's implementation.

## References

- Original write-up: `~/projects/private_specs/uniterm/spec/research/original-writeup.md`, APPLET-8 and CONTROL-3

# UTERM-008: Map Viewer Applet

**Status:** draft
**Created:** 2026-10-31
**Updated:** 2026-10-31

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

## References

- Original write-up: `~/projects/private_specs/uniterm/spec/research/original-writeup.md`, APPLET-8 and CONTROL-3

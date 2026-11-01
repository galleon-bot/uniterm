# UTERM-011: Widget Bar

**Status:** deferred
**Created:** 2026-10-31
**Updated:** 2026-10-31
**Revisit:** when UTERM-001 M4 is DONE and the widget mockups are added to the repo

## Dependencies

- UTERM-001

## Summary

A widget bar region holds small widgets. Each widget shows an icon and up to three lines of text.

## Motivation

Some information is worth seeing at a glance, such as a build status or a clock. The status bar holds single lines. The
widget bar gives a little more room per item.

## Design Decisions (Settled)

### The widget bar is a region

It is a region, as defined in UTERM-001. Its position is a setting.

### Widget size

A widget takes a small amount of vertical space. It shows an icon plus at most three lines of small text. A large line
may take the space of two small lines.

### Deferred until the status bar exists

The write-up puts the status bar first. This proposal waits until UTERM-001 M4 is done and the mockups are in the repo.

## Design Decisions (Open)

### Combine with the status bar?

The write-up asks whether the widget bar and the status bar could be one region. Options: two regions, or one region
with two densities.

### Widget sources

Where widgets come from: built-in, applets, Janet scripts, or programs.

## Risks

None identified. The proposal is deferred and commits to nothing yet.

## Milestones

### M1: Widget bar with one built-in widget

**Status:** NOT STARTED

- A window can show a widget bar region
- One built-in widget shows an icon and up to three lines of text, matching the mockups

## Decision Log

- 2026-10-31: Deferred. The write-up marks the widget bar as not fully worked out, and says the status bar comes first.
  Revisit when UTERM-001 M4 is done and the mockups are in the repo.

## References

- Original write-up: `~/projects/private_specs/uniterm/spec/research/original-writeup.md`

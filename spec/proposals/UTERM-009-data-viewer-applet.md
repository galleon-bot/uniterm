# UTERM-009: Data Viewer Applet

**Status:** draft
**Created:** 2026-10-31
**Updated:** 2026-11-01

## Dependencies

- UTERM-001

## Summary

A table viewer applet for CSV, JSON, and spreadsheet data. It supports filtering, sorting, and searching.

## Motivation

Tabular output is hard to read in a terminal. A table pane lets the user sort and filter it without leaving uniterm.

## Design Decisions (Settled)

### Table first

The applet shows data as a table. It supports filtering, sorting, and searching.

### Charts are out of scope

Charts and graphs are not part of this proposal. The write-up flags them as complex. A later proposal may add them.

## Design Decisions (Open)

### Spreadsheet formats

macOS has no built-in reader for Excel files. Options:

- **Support `.xlsx` through a Swift library,** such as CoreXLSX.
- **Skip spreadsheets at first.** Ship CSV and JSON only.
- **Also support legacy `.xls`.** This needs a separate library.

### JSON shapes

How JSON maps to a table. An array of flat objects is easy. Nested objects and arrays need a rule: flatten, show as
expandable cells, or reject.

### Large files

- A size limit, or streaming rows for large files.
- Whether sorting and filtering run off the main thread.

### Input sources

Whether data can arrive from a script or a pipe, as well as from a file.

### The applet contract

Context from UTERM-001, which shipped the applet contract. An ADR for the contract is a candidate in UTERM-001's
Decision Log. This proposal may reshape it, so it is not written yet. Every applet implements:

- A view the pane hosts, a title, and status bar segments.
- `start`, `close`, `focus`, and a palette update.
- `detach` and `reattach`. A closed pane's applet is hidden and kept alive for 10 seconds, so undo can bring back the
  exact session.
- `isRunningSomething` and `runningLabels`. Closing a window or quitting asks first when any visible or hidden pane is
  running something, and the dialog names it.
- `describe()`, an inert description with a type and a per-type version. Undo past the grace period and layout restore
  both rebuild the applet from it. ADR-03 says restoring it never runs a program the user did not ask for. A
  description this build cannot read is kept byte-for-byte in a placeholder pane.

For the data viewer: a description likely holds the source file and the sort and filter state. When the data came from
a command's output, restoring must not run that command again.

## Risks

- **A huge file freezes the pane** — likelihood: medium, impact: medium.
  Mitigation: settled with the large files decision above.

## Milestones

### M1: CSV table

**Status:** NOT STARTED

- A pane can run the data viewer and open a CSV file as a table
- Clicking a column header sorts by that column
- A filter field hides rows that do not match

### M2: JSON

**Status:** NOT STARTED

- An array of JSON objects opens as a table, one column per key
- Nested values follow the settled JSON shapes rule

### M3: Search

**Status:** NOT STARTED

- Searching highlights matching cells and steps between them

## Decision Log

- 2026-10-31: Drafted from the original write-up without an interview. The open questions hold everything undecided.
- 2026-11-01: Added "The applet contract" with context from UTERM-001's implementation.

## References

- Original write-up: `~/projects/private_specs/uniterm/spec/research/original-writeup.md`, APPLET-4

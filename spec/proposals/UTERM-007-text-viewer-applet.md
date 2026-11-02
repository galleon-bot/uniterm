# UTERM-007: Text Viewer Applet

**Status:** draft
**Created:** 2026-10-31
**Updated:** 2026-11-01

## Dependencies

- UTERM-001

## Summary

A read-only document viewer applet. It shows Markdown, RTF, Word documents, and PDFs.

## Motivation

READMEs, specs, and reports often need reading beside a terminal. A viewer pane renders them properly instead of as raw
text.

## Design Decisions (Settled)

### Read-only

The applet views documents. It does not edit them.

### PDFs use PDFKit

PDFs render with PDFKit's `PDFView`.

### RTF and Word use the system readers

RTF and Word documents load through `NSAttributedString`'s document readers and display in a text view.

## Design Decisions (Open)

### Markdown rendering

Foundation's Markdown parsing focuses on inline styles. It does not lay out full documents with tables and code blocks.
Options:

- **Render HTML in a `WKWebView`.** Convert Markdown to HTML with a library. Full layout and easy theming with CSS.
- **A native Markdown renderer.** A Swift library that renders to native views or attributed strings.
- **QuickLook.** Depends on what Markdown support the system provides.

### Live reload

Whether the viewer reloads when the file changes on disk. Useful while editing a document in a terminal.

### Search and navigation

- Find in document.
- A table of contents from headings or PDF outlines.

### Control levels

Which UTERM-004 levels the viewer supports. The presentation example would send speaker notes here.

### The applet contract

Context from UTERM-001, which shipped the applet contract. ADR-05 and ADR-06 cover its lifecycle and its description
versioning. An ADR for the rest of the contract is a candidate in UTERM-001's Decision Log. This proposal may reshape
it, so it is not written yet. Every applet implements:

- A view the pane hosts, a title, and status bar segments.
- `start`, `focus`, and a palette update.
- `detach`, `reattach`, and `close`. uniterm sends these lifecycle events, and each applet owns its response, per
  ADR-05. On detach an applet pauses audio, video, and alerts at once. uniterm keeps no closed applet alive. An applet
  that keeps work going after close owns its bound and a visible indicator.
- `isRunningSomething` and `runningLabels`. Closing a pane, a window, or the app asks first when an affected pane is
  running something, and the dialog names it.
- `describe()`, an inert description with a type and a per-type version. Undo and layout restore both rebuild the
  applet from it, in the same place. Undo is not a snapshot of running state. An applet that wants undo to bring back
  more saves it in its description. ADR-03 says restoring it never runs a program the user did not ask for. ADR-06
  says the applet owns its payload and its version. It upgrades its own older versions, and bumps the version on any
  change an older build cannot round-trip. A description this build cannot read is kept byte-for-byte.

For the text viewer: a description likely holds the file path and the scroll position. A read-only viewer likely never
counts as running something.

## Risks

- **Word documents render imperfectly through the system reader** — likelihood: high, impact: low.
  Accepted: the viewer is for reading, not for faithful layout. Users needing exact layout can open the file in Word or
  Pages.

## Milestones

### M1: PDF and RTF

**Status:** NOT STARTED

- A pane can run the text viewer and open a PDF
- The viewer opens RTF and Word documents
- Pages scroll and text can be selected and copied

### M2: Markdown

**Status:** NOT STARTED

- The viewer renders Markdown headings, lists, code blocks, tables, and links
- Rendered Markdown uses the current theme's colors

## Decision Log

- 2026-10-31: Drafted from the original write-up without an interview. The open questions hold everything undecided.
- 2026-11-01: Added "The applet contract" with context from UTERM-001's implementation.

## References

- Original write-up: `~/projects/private_specs/uniterm/spec/research/original-writeup.md`, APPLET-7

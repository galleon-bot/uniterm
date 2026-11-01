# UTERM-006: Image Viewer Applet

**Status:** draft
**Created:** 2026-10-31
**Updated:** 2026-11-01

## Dependencies

- UTERM-001

## Summary

An image viewer applet. It shows one image, or steps through the images in a folder as a slideshow.

## Motivation

Viewing images from the terminal usually means leaving uniterm for Preview or Finder. An image pane keeps them beside
the work that produced them.

## Design Decisions (Settled)

### Folder slideshow

Given a folder, the applet steps through its images in order. Given one file, it shows that file and can step through
its siblings.

## Design Decisions (Open)

### Rendering

Options:

- **QuickLook's `QLPreviewView`.** Broad format support for free. The write-up notes QuickLook is not always pleasant.
- **A custom view on ImageIO.** Full control over zoom, panning, and transitions. Handles only image formats.
- **QuickLook first, then a custom view.** A quick start, replaced when its limits show.

### Navigation

- Keyboard keys for next, previous, first, and last.
- Whether the slideshow advances on a timer.
- Sort order: name, date, or both.

### Zoom

Fit to pane, actual size, and free zoom with panning.

### Control levels

Which UTERM-004 levels the viewer supports. A script might send it an image or a folder to show.

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

For the image viewer: a description likely holds the folder and the current image. The viewer likely never counts as
running something.

## Risks

- **Large folders load slowly** — likelihood: medium, impact: low.
  Mitigation: load images lazily and prefetch only neighbors.

## Milestones

### M1: Show one image

**Status:** NOT STARTED

- A pane can run the image viewer and show a chosen image
- The image fits the pane and rescales when the pane resizes

### M2: Folder slideshow

**Status:** NOT STARTED

- Given a folder, the viewer steps forward and back through its images by keyboard
- Non-image files in the folder are skipped

## Decision Log

- 2026-10-31: Drafted from the original write-up without an interview. The open questions hold everything undecided.
- 2026-11-01: Added "The applet contract" with context from UTERM-001's implementation.

## References

- Original write-up: `~/projects/private_specs/uniterm/spec/research/original-writeup.md`, APPLET-5

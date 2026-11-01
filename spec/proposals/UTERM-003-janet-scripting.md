# UTERM-003: Janet Scripting and REPL

**Status:** draft
**Created:** 2026-10-31
**Updated:** 2026-10-31

## Dependencies

- UTERM-001

## Impacts

- UTERM-002 — "Host API": the palette may run its commands through it
- UTERM-004 — "Host API" and "Sandboxing": control levels limit what scripts may do to panes

## Summary

uniterm embeds Janet. A small host API lets scripts list panes, open applets and tabs, and send content to applets.
Scripts run from the command line with `uniterm run file.janet`, or interactively in a REPL applet.

## Motivation

The write-up asks for a low-level, scriptable control layer beneath the command palette. A Lisp keeps that layer small
and easy to extend. Janet is already the chosen embedded Lisp for Swift hosts in the coding standards.

## Design Decisions (Settled)

### Janet is the embedded language

Janet is vendored from one tagged release and compiled into the app. It follows the embedding rules in the coding
standards: one owning thread, `janet_pcall` at every entry, rooted values, and a sandbox.

### Host API

- The host API is a small, named set of functions in its own Janet module.
- The API has a version. Scripts can check it.
- Every host function validates its arguments. Bad input returns an error to the script. It never crashes the app.

A first set of functions:

- List windows, panes, and applets.
- Open a pane with a given applet.
- Open a tab in an applet that supports tabs.
- Send a document or data to an applet for display.
- Post a status bar message.

### Two entry points

- `uniterm run file.janet` runs a script against a running uniterm.
- A REPL applet runs in a pane. It evaluates Janet against the same API.

### Sandboxing

Scripts are denied file, network, process, and FFI access unless their job needs it. A watchdog bounds CPU time.

## Design Decisions (Open)

### How `uniterm run` reaches the app

Options:

- **A Unix domain socket** owned by the running app. The CLI sends the script or its path.
- **XPC.** Native to macOS, with built-in peer identity.
- **Run the script in the CLI process,** sending API calls to the app. Keeps the app's VM untouched.

The choice also shapes UTERM-004's trust model, since the app must know who is calling.

### Where scripts run

- One VM for the app, or one VM per script or REPL.
- Which thread owns each VM. AppKit work must happen on the main thread.

### API naming and shape

- Function names and namespaces.
- How panes are identified: stable IDs, paths in the tree, or both.

### REPL features

- History, completion, and multi-line input.
- Whether the REPL applet is built on the terminal applet, or is a native text view.

## Risks

- **The host API becomes a public contract that scripts depend on** — likelihood: high, impact: medium.
  Mitigation: version the API from the first release. Keep the first set small.
- **A Janet panic unwinds through Swift frames** — likelihood: medium, impact: high.
  Mitigation: every call into Janet goes through one boundary using `janet_pcall`. Fixture tests cover panics.
- **A runaway script freezes the app** — likelihood: medium, impact: high.
  Mitigation: run Janet off the main thread with a watchdog interrupt.

## Milestones

### M1: Embedded Janet and the first host function

**Status:** NOT STARTED

- Janet is vendored from a recorded tagged release and builds with the app
- One host function, such as posting a status message, works from a script
- A script error is reported with the script name, line, and message, and the app keeps running

### M2: Host API v1

**Status:** NOT STARTED

- Scripts can list windows and panes, open a pane with an applet, and open a terminal tab
- Each host function rejects bad arguments with an error to the script
- Script fixtures exercise every host function, including error cases, in `make test`

### M3: `uniterm run`

**Status:** NOT STARTED

- `uniterm run file.janet` runs the script against the running app
- With no app running, the command reports that clearly

### M4: REPL applet

**Status:** NOT STARTED

- A pane can run the REPL applet
- Expressions typed in the REPL call the host API and show results

### M5: Sandbox and limits

**Status:** NOT STARTED

- A script fixture that tries a denied operation fails with the expected error
- A script in an infinite loop is interrupted, and the app stays responsive

## Decision Log

- 2026-10-31: Drafted from the original write-up without an interview. The open questions hold everything undecided.

## References

- Original write-up: `~/projects/private_specs/uniterm/spec/research/original-writeup.md`, APPLET-9
- Coding standards: `languages/janet.md` and `languages/lisp-embedding.md`

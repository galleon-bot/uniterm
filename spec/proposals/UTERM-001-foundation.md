# UTERM-001: Foundation

**Status:** draft
**Created:** 2026-10-31
**Updated:** 2026-10-31

## Summary

This proposal builds the base of uniterm. The app opens one or more windows. Each window holds a tree of resizable split
panes. Each pane runs one applet. Each window has a status bar that can dock at the top or the bottom.

The first applet is a terminal built on libghostty. It runs the user's shell in tabs, or one program without tabs.

Closing a pane can be undone. Window and pane layouts are restored across launches.

## Motivation

uniterm aims to be more than a terminal emulator. Later work adds a command palette, a widget bar, more applets, Janet
scripting, and controls for scripts that drive panes. All of it needs the same base: windows, regions, a pane tree, an
applet contract, and a status bar.

A terminal is the first applet because it is the core use. It also tests the applet contract against a demanding case:
a live process, keyboard input, GPU rendering, and resizing.

## Design Decisions (Settled)

### Platform and UI framework

uniterm is a Swift app for macOS 26 and later. AppKit owns the windows, the pane tree, and applet hosting. SwiftUI is
allowed for small leaf views, such as status bar segments.

Rationale: a nested split tree that hosts AppKit views is easier in AppKit. Those views include a Metal terminal
surface, and later a web view, a QuickLook view, and a map. Targeting macOS 26 allows the newest AppKit APIs. It also
matches the Swift 6.2 toolchain that the community libghostty packages require.

### Window chrome

Each window is an `NSWindow` with a full-size content view. Content extends up under the title bar. The standard
traffic-light buttons stay.

### Regions are separate from position

A region is a logical part of a window. Its role never changes. Where it docks is a separate setting.

This proposal defines two regions:

- The main content area, which holds the pane tree.
- The status bar, which docks at the top or the bottom of the window.

The command palette and the widget bar become regions in later proposals. The region model must let them join without
changes to the status bar or the content area.

### Status bar

- Each window has one status bar. It is always docked.
- The bar is split into segments. A segment shows a small icon or one line of text, with light formatting such as color.
- Anything in the window may post a message to the window's status bar. Messages queue.
- The bar can expand to show more than one line, such as a history of past messages.

### Panes and applets

- The main content area holds a tree of panes. A pane splits horizontally or vertically, and splits nest.
- Panes are resizable. A pane has a minimum usable size. A split that would push a pane below it is refused.
- A pane runs exactly one applet. The same applet type may run in many panes.
- Opening a new pane asks the user which applet to start.
- Closing a pane closes its applet and every tab the applet has.

### One terminal applet with two modes

The terminal applet covers both APPLET-1 and APPLET-2 from the original write-up:

- Shell mode starts the user's default shell. It supports multiple tabs. Each tab is an independent tty.
- Program mode starts one given executable in one tab, with no new-tab action.

The tab bar is hidden when the applet has only one tab.

Rationale: the write-up says APPLET-2 can be APPLET-1 with a setting, if that is enough. The two modes differ only in
what they launch and whether new tabs are allowed.

### Terminal surface behind an internal protocol

The terminal applet talks to libghostty through an internal protocol owned by uniterm. No libghostty type appears
outside that boundary.

Rationale: libghostty's API is not stable. The boundary limits churn to one module. It also keeps a fallback to
SwiftTerm possible. See Risks.

### Theming

The default theme is Catppuccin Latte. A dark Catppuccin theme ships too. Colors are defined as named tokens in one
place. Applets and regions read the tokens, never raw colors.

### Scope

In scope:

- Multiple windows
- Terminal tabs
- Undo for closing a pane
- Layout persistence across launches

Out of scope, for later proposals:

- The command palette
- The widget bar
- Janet scripting and the REPL applet
- Remote control and trust between panes (CONTROL-1, CONTROL-2, CONTROL-3)
- Shell blocks in the terminal
- Applets other than the terminal

## Design Decisions (Open)

### How to get libghostty

Options:

- **A community prebuilt package**, such as `loeschg/GhosttyKit` or `rijieli/libghostty-spm`. Fastest start. It depends
  on a third party tracking Ghostty. `rijieli/libghostty-spm` has withdrawn tagged releases before.
- **Vendor Ghostty and build the xcframework from source.** Full control over the version. It needs a Zig toolchain in
  the build.
- **Wait for the first-party Swift package** that Mitchell Hashimoto announced in July 2026. It was not confirmed shipped
  as of 2026-10-31.

The fallback in every case is SwiftTerm, behind the same internal protocol.

### Build system

Options:

- **SwiftPM plus a script** that assembles the `.app` bundle. Plain text, easy to diff. Bundling, signing, and
  entitlements need custom work.
- **An Xcode project.** Native app bundling and signing. The project file is hard to review and merge.
- **A generated Xcode project**, from XcodeGen or Tuist. Reviewable spec files, with Xcode's bundling. It adds a tool.

### Pane tree shape

Options:

- **Binary tree.** Each split node has exactly two children and one ratio. Simple to reason about. Three equal columns
  need nested splits.
- **N-ary tree.** Each split node has many children along one axis, with a ratio per child. Matches how users think of
  rows and columns. Resizing and removing children is more complex.

### What undo close restores

A terminal's process dies when its pane closes. Options:

- **Keep the closed applet alive, hidden, for a grace period.** Undo returns the exact session. Closed processes keep
  running briefly, which may surprise the user.
- **Restore the layout and relaunch.** Undo reopens the pane, with the shell in the same working directory. The process
  and scrollback are lost.
- **Applet-defined.** Each applet says what it can restore. The terminal picks one of the above.

Also open: how many closes undo remembers, and for how long.

### What layout persistence restores, and in what format

- What is restored: windows, frames, the pane tree, applet types, and region docking are the minimum. Terminal working
  directories, tab titles, and scrollback are candidates.
- The file format and its location, and how it is versioned.

### Dark theme flavor and switching

- Which dark flavor: Frappé, Macchiato, or Mocha.
- Whether the theme follows the system appearance, uses an explicit setting, or both.

### Status message model

- Whether messages carry a priority, a level such as info or error, or both.
- How long a message stays before the next one in the queue replaces it.
- Who owns a segment: fixed segments per window, segments an applet claims, or both.

### Naming

"Pane", "applet", and "region" are working names. They avoid clashes with Swift and AppKit names such as `View`. Better
names may still be found. Settle them before M3, since type names follow from them.

## Risks

- **libghostty's API changes between releases** — likelihood: high, impact: medium.
  Mitigation: pin an exact version. Keep every libghostty call behind the internal terminal surface protocol. Keep
  SwiftTerm as a tested fallback path if an upgrade becomes too costly.
- **The applet contract becomes the base for every later applet** — likelihood: medium, impact: high.
  Mitigation: the contract is internal, not published. Exercise it with the terminal in M2 and M5 before other applets
  build on it. Expect to revise it when the second applet arrives.
- **The persisted layout format is a stored format that later versions must read** — likelihood: high, impact: medium.
  Mitigation: give the file a version field from the first release. On a version it cannot read, uniterm starts with a
  default layout and keeps the old file aside.
- **Undo close keeps live processes the user thinks are gone** — likelihood: medium, impact: medium.
  Mitigation: settled with the undo option above. If processes are kept alive, the grace period is short and shown in
  the status bar.
- **Full-size content conflicts with title bar dragging and the traffic lights** — likelihood: medium, impact: low.
  Mitigation: M1 checks that the window drags, and that the traffic lights stay clickable and unobscured.
- **The proposal is large and may stall before a usable app exists** — likelihood: medium, impact: medium.
  Mitigation: the milestones are ordered so a usable single-window terminal lands by M2. Later milestones can move to a
  new proposal if this one stalls.

## Milestones

### M1: App skeleton and theme tokens

**Status:** NOT STARTED

- `make build` produces a `.app` bundle that launches on macOS 26
- The app opens one window with a full-size content view and working traffic lights
- The window drags by its top edge, and content does not cover the traffic lights
- Catppuccin Latte and the dark theme are defined as named color tokens in one place
- `make test` runs and passes

### M2: Terminal applet in a single pane

**Status:** NOT STARTED

- The window's content area hosts one pane running the terminal applet
- The terminal starts the user's default login shell and accepts keyboard input
- The terminal resizes with the window, and the shell sees the new size
- No libghostty type is visible outside the terminal surface module
- When the shell exits, the pane closes

### M3: Pane tree

**Status:** NOT STARTED

- A pane splits horizontally and vertically, and splits nest
- Dragging a divider resizes the panes on either side
- A split that would push a pane below its minimum size is refused
- Keyboard focus moves between panes, and the focused pane is visible
- Opening a new pane asks which applet to start
- Closing a pane closes its applet and gives its space to its neighbors

### M4: Status bar region

**Status:** NOT STARTED

- Each window has a status bar that docks at the top or the bottom
- Changing the dock position does not change what the status bar shows
- An applet can post a message to its window's status bar, and messages queue
- The status bar shows segments with an icon or one line of styled text
- The status bar expands to show the history of messages

### M5: Terminal tabs and program mode

**Status:** NOT STARTED

- A terminal applet in shell mode opens, switches, and closes tabs
- Each tab runs an independent tty
- The tab bar is hidden when the applet has one tab
- A terminal applet in program mode runs a given executable in one tab, with no new-tab action
- Closing a pane closes every tab in its applet

### M6: Multiple windows

**Status:** NOT STARTED

- The user can open more than one window
- Each window has its own pane tree and its own status bar
- A status message posted in one window does not appear in another

### M7: Undo close pane

**Status:** NOT STARTED

- After closing a pane, undo reopens it in its former place in the tree
- The restored terminal behaves as the settled undo decision says
- Undo behaves as settled when the closed pane's neighbors have since changed

### M8: Layout persistence

**Status:** NOT STARTED

- Quitting and relaunching restores every window's frame, pane tree, applet types, and region docking
- The saved file carries a version field
- A saved file with an unreadable version leads to a default layout, and the old file is kept aside

## Decision Log

- 2026-10-31: Chose Swift, AppKit first with SwiftUI for leaf views, Janet for scripting, and libghostty for the
  terminal.
- 2026-10-31: Set macOS 26 as the minimum version.
- 2026-10-31: Put multiple windows, terminal tabs, undo close, and layout persistence in this proposal's scope.

## References

- Original write-up: `~/tmp_work/uniterm.md`
- [Ghostty](https://ghostty.org/docs/about): libghostty is not yet a stable API
- [loeschg/GhosttyKit](https://github.com/loeschg/GhosttyKit)
- [rijieli/libghostty-spm](https://github.com/rijieli/libghostty-spm)
- [Mitchell Hashimoto on the Swift renderer package](https://x.com/mitchellh/status/2072724957902381319)

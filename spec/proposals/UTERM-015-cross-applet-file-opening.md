# UTERM-015: Cross-Applet File Opening

**Status:** draft
**Created:** 2026-11-03
**Updated:** 2026-11-03

## Dependencies

- UTERM-001
- UTERM-002's command registry and UTERM-013: File > Open is a registry command, and its key falls under shortcut
  ownership
- UTERM-003 M3: a `uniterm open` command, if "Which entry points open files" keeps it, uses the `uniterm` command and
  its listener
- UTERM-004 M1, M3, and M6: the path-reading power builds on caller identity, shared command dispatch, and the
  permission scopes and approval flow

## Impacts

- UTERM-006 — "Input sources" and "Control levels": this proposal is the cross-applet proposal its revisit hook asks
  for, and it defines the path-reading power its M4 uses
- UTERM-009 — "Input sources": this proposal is the cross-applet file-opening proposal its revisit hook commits to.
  App-level opening and the data viewer's File > Open binding are decided here
- UTERM-008 — "Input sources" file source: its open panel and drop stay in the pane. Finder and File > Open reach the
  map through the router
- UTERM-008 — "Where pins come from": `pin selected` names a file pin by its ID, which comes from the user's file. Under
  "The path-reading power", a driver whose scope does not hold the file gets no such detail. UTERM-008 needs an
  amendment when this proposal is accepted
- UTERM-007 — the text viewer, still a draft, opens its documents through the same router and declares the types it
  opens
- UTERM-005 — "Navigation": the browser refuses `file:` because loading it needs a file read scope. That scope is the
  path-reading power defined here, so a later change to the browser's `file:` rule builds on it
- UTERM-004 — "Permission scopes and approval flow": adds the path-reading power to the typed permission set

## Summary

One way for a file to reach an applet from outside its pane. Finder, the Dock, File > Open, and possibly a `uniterm
open` command and terminal clicks all hand a file to one router. The router picks an applet from the file's type, places
a pane, and hands the file to that applet's source-taking entry point. This proposal also defines the path-reading power
under ADR-09, which lets a controller ask an applet to read a path inside an explicit directory scope.

## Motivation

UTERM-009 settled that viewers open files from inside their own pane, with an open panel or a drop. It left app-level
opening to one cross-applet proposal, because UTERM-006, UTERM-007, UTERM-008, and UTERM-009 all open files, and
deciding it inside one applet would change the factory every applet implements. Its revisit hook requires this proposal
to be filed before a second viewer among UTERM-006 to UTERM-008 starts its first milestone. UTERM-006 M1 is gated on it
directly.

UTERM-006 also settled that asking an applet to read a path is a power of its own under ADR-09, apart from pane
control. ADR-09 lists no such power, and UTERM-005, UTERM-006, UTERM-007, and UTERM-009 each need the same one. One
definition keeps them from diverging.

Today the app has no file-open path at all. It declares no document types, binds no Cmd-O, has no `uniterm` command,
and ignores link and path clicks in the terminal. Every viewer bound no File > Open shortcut while waiting for this
decision.

## Design Decisions (Settled)

### Scope

This proposal covers how a file reaches an applet from outside that applet's pane, and the power a controller needs to
make an applet read a path.

Out of scope:

- Opening inside a pane, by open panel or drop. Each viewer's proposal settles that, and it stays as settled.
- Byte-stream sources, pipes, and data with no file. UTERM-009's revisit hook keeps them, tied to UTERM-003 and
  UTERM-004.
- A drawer of open documents in one pane. UTERM-006 and UTERM-009 leave it to its own proposal.
- Editing files. Every viewer is read-only.
- Opening anything other than a local file or folder, such as a web URL clicked in the terminal.

Rationale: these are the parts UTERM-006 and UTERM-009 handed to a cross-applet proposal, and no more.

### One route from a path to a pane

Every app-level entry point hands its files to one router. The router hands each file to the chosen applet through the
same source-taking entry point the applet's own open panel and drop use.

Rationale: UTERM-006 rejected a launcher path field because it would be a second route from a path to a pane. One
route means the size limits, the type checks, the bookmark rules, and the error messages each viewer settled apply to
every way a file arrives.

### The path-reading power

Asking an applet to read a path on a controller's behalf is its own power under ADR-09. This proposal defines it once
for every applet, with the shape UTERM-006 settled:

- It is separate from pane control. Control of a pane grants no read, and a read grant controls no pane.
- It carries an explicit directory scope. The canonical path is checked against the scope before anything is
  opened, so an out-of-scope request never touches the file, and never raises a macOS privacy prompt under uniterm's
  name. The open does not block and does not follow a final symlink, and the opened descriptor must be a regular file
  or a folder. The real path of the opened descriptor is then checked again, so a symlink or a rename between check
  and open cannot widen it. Amended 2026-11-03; see Decision Log.
- Errors for paths outside the scope do not tell "missing", "not a supported type", and "denied" apart.
- When a pane's source lies outside the controller's scope, because the user opened it or a restore found it, events
  and replies to that controller carry no path or content detail from it.
- A file the user picks in Finder, on the Dock, in File > Open, or in a pane's own open panel or drop is the user's
  act, not a controller's. It needs no grant. `uniterm open` and terminal clicks are not covered by this rule, since a
  program chooses what they name. Their own questions decide their authority. Amended 2026-11-03; see Decision Log.

Rationale: UTERM-006 settled this shape in review, and the user kept it at the review gate. Without a scope, a script
with no file capability could probe which files exist, and borrow uniterm's macOS privacy grants for Downloads,
Documents, and Desktop. The scope protects controllers that have no file access of their own. A process uniterm
starts, such as a shell or an exec driver, already holds those grants directly, and the scope does not change that.
The grant's declaration and approval are open. See "How the path-reading power is granted".

## Design Decisions (Open)

### Which entry points open files

Which app-level ways to open a file this proposal builds.

- **Finder, Dock, and File > Open, plus `uniterm open` and terminal clicks.** The complete set. Terminal clicks need
  uniterm to handle libghostty's open-URL action and hyperlinks, which it ignores today. Adds a milestone for clicks.
  `uniterm open` brings in "Who may run `uniterm open`".
- **Finder, Dock, File > Open, and `uniterm open`.** Leaves undone: a path printed in the terminal still needs copying
  into a command.
- **Finder, Dock, and File > Open only.** Needs no caller identity, so it can land before UTERM-003 and UTERM-004.
  Leaves undone: a terminal user cannot open a file beside the terminal without leaving the keyboard.

### How a file type maps to an applet

Several applets can read one type. `.json` suits the data viewer and the text viewer. `.geojson` suits the map, the
data viewer, and the text viewer. `.md` and `.pdf` go to the text viewer, and `.svg` to the image viewer.

- **Each applet type declares the content types it opens, with a rank.** The router picks the most specific conforming
  type, then the highest rank. A setting lets the user pick the applet for a type. Declarations live with the applet,
  so a new applet needs no host change.
- **A host-owned table from type to applet.** One place to read, but every new applet edits the host.
- **Ask every time when more than one applet can open the file.** No wrong guess, but an extra step on every common
  open.
- **Each applet declares types with a rank, plus an "Open With" choice for one open, and no setting.** The rank
  decides every default. The user overrides a single open. Leaves undone: a user who always wants `.json` in the text
  viewer picks it every time.
- Any option with a setting must say what happens when the setting names an applet type that no longer exists.
- Any option may pair with an "Open With" choice in uniterm, for overriding one open.

### Where a routed pane goes

- **Beside the focused pane, as Split Right does.** In a new window when no window is open, such as an open from
  Finder at launch.
- **Into the focused pane when it is a launcher or an empty pane of the chosen type, else beside it.**
- **Finder and Dock opens in a new window, in-app opens beside the focused pane.** Matches how a document app behaves
  for a Finder open.
- Each option needs a rule for a split refused for lack of room. Candidates: a new window, a new tab in the window, or
  refusing with the "not enough room" message the window already posts.
- Each option needs a rule for a Finder open that arrives at launch while layout restore runs: whether the routed pane
  lands after restored windows, or in its own window.
- Constraint: a routed open never lands in a pane a controller owns. Otherwise a controller could place an empty pane
  to learn when the user opens a file.

### Who owns Cmd-O

UTERM-013 makes every key on a non-applet menu item a reserved window key, so an applet can never also bind it.

- **File > Open is a window command on Cmd-O. It always goes through the router.** Works the same in every pane.
  Reserves Cmd-O, so no applet can use it.
- **Open is an applet command each viewer declares on Cmd-O, opening into that pane.** The terminal and the launcher
  then have no Open.
- **Both: File > Open on Cmd-O through the router, and an "Open in This Pane" applet command with no default chord.**
  The pane-local open stays reachable from the menu and the palette.

### Which file types uniterm registers with Finder

Launch Services reads document types from the app's `Info.plist`, which cannot change at run time.

- **Register every declared type at the Alternate rank.** uniterm shows under Open With and never takes a default from
  another app. A test fails when the plist and the applet declarations disagree.
- **Register at the Default rank.** uniterm can become the default for types it registers. It can take a default
  quietly on install.
- **Register no document types.** Finder can still open a file by a drop on the Dock icon only if types are declared,
  so this rules out Finder and Dock opens.

### Several files at once

Every viewer shows one source per pane and refuses a drop of several files.

- **One pane per file, routed per file, with a confirmation above a fixed count.** Mixed types work.
- **Refuse with a message asking for one file.** Matches the in-pane drop rule.
- **Open the first file and post a message naming the rest.**

### Folders

Finder and `uniterm open` can pass a folder. The image viewer accepts one as a slideshow source. A terminal could start
a shell in it.

- **Route a folder like a file, with the folder as its content type.** The image viewer and the terminal both declare
  folders. The type mapping question picks between them.
- **Folders always open a terminal there.** Simple, but a slideshow then needs the in-pane open panel.
- **Refuse folders.**

### Start directory and current directory

uniterm's rules require that current directory flows explicitly, never as hidden state. This question decides each flow
the router adds.

- The routed pane's start directory. Candidates: the opened file's folder, the focused pane's `currentDirectory`, or
  none.
- File > Open's panel start directory. Candidates: the focused pane's `currentDirectory`, the last folder File > Open
  used, kept explicitly per window, or the panel's own remembered folder.
- A relative path given to `uniterm open`. Candidates: the command resolves it against its own working directory
  before it sends anything, so the app only sees absolute paths, or relative paths are refused. UTERM-003 says the
  CLI's working directory never flows in implicitly. Resolving a path the user typed in that directory may or may not
  count as implicit flow.
- A relative path clicked in the terminal, if "Which entry points open files" keeps clicks. The shell's directory when
  the path was printed may differ from its directory now. Candidates: resolve against the directory recorded for the
  output's command, refuse relative paths, or resolve against the current `currentDirectory` and accept the mismatch.
- Constraint: a terminal in an ssh session reports a remote directory, and a `file://host/path` hyperlink can name
  another host. Neither may be read as a local path.

### Who may run `uniterm open`

Only when "Which entry points open files" keeps `uniterm open`. Opening a pane from a process is a control effect under
ADR-09. The listener knows the peer's audit token and PID, but ADR-09 says a request from a terminal session that cannot
identify its originating program cannot use a particular script's approval.

- **A once or session approval scoped to the calling terminal session, labelled as covering programs in that
  session.** The same shape UTERM-004 gives anonymous OSC 52. The first open in a session asks.
- **A `uniterm open` request needs a controller grant, like any `uniterm run` script.** Consistent with every other
  control entry point. A user typing `uniterm open` sees an approval prompt, and remembered trust needs a verified
  controller.
- **Treat it as the user's act, since the command only opens a pane and returns no content.** The caller learns nothing
  it could not read itself. Any same-user process can then open panes, which ADR-09's scope rules exist to prevent.
- Constraint: the reply to `uniterm open` carries no file content, so the path-reading power may not be needed for it.
  Opening a pane may still need pane-creation authority.
- Constraint: a reply that says a file is missing, or names its type, tells the caller what exists. Without the
  path-reading power for that path, the reply must not tell "missing", "unsupported", and "denied" apart. The user
  still sees the full message in uniterm.

### How the path-reading power is granted

The settled shape says what the power does. This question says how a controller gets it.

- **A typed permission in UTERM-004's set, with the same directory scope type its host-launch grant uses.** Declared at
  startup, approved through the existing panel, covered by an unchanged or narrower request.
- **A per-request approval for each path.** No remembered state. Prompts on every read a controller makes.
- Sub-questions for either option: whether a scope is one directory or a list, and whether a scope that contains a
  macOS-protected folder, such as home containing Documents, must name that folder explicitly.

## Risks

- **Registering document types takes Finder defaults from other apps** — likelihood: medium, impact: medium. A Default
  rank can make uniterm the default for `.json` or `.md` on install. Mitigation: "Which file types uniterm registers
  with Finder" lists the Alternate rank, and a test checks the plist.
- **Launch Services caches what uniterm registers** — likelihood: medium, impact: low. A type dropped in a later
  release can linger under Open With until Launch Services re-registers the app. Accepted: the stale entry opens
  uniterm, and the router refuses a type no applet declares, with a message.
- **The path-reading power diverges from what a viewer built first** — likelihood: medium, impact: medium. UTERM-009 and
  UTERM-008 are scheduled before this proposal is accepted. Mitigation: neither builds a controller file read before
  this proposal's power exists, and UTERM-006 M4 depends on it.
- **A controller borrows uniterm's macOS privacy grants** — likelihood: medium, impact: high. Once the user lets
  uniterm read Documents, any applet read runs with that grant. Mitigation: the settled directory scope, checked before
  the open and again on the opened descriptor, for controllers with no file access of their own. Accepted for the
  rest: shells and exec drivers uniterm starts hold the grants directly, which the scope cannot change.
- **A hard link inside the scope reaches a file outside it** — likelihood: low, impact: medium. A hard link has no
  other real path, so a path check cannot see that the inode also lives elsewhere. Accepted: making one needs write
  access to a directory in the scope, on the same volume, and the controller already reads what the scope holds.
- **Draft applets change what they claim** — likelihood: medium, impact: low. UTERM-007 and UTERM-010 are drafts.
  Accepted: declarations live with each applet, so a later claim changes no router code.
- **No viewer applet exists in code yet** — likelihood: high, impact: low. The router cannot be tested against real
  viewers at first. Mitigation: the router's milestones test with fixture applets, as UTERM-004 M4 does.

## Milestones

The milestones below assume the complete option of "Which entry points open files". Answers to the open questions may
remove, add, or reshape them.

### M1: The router

**Status:** NOT STARTED

- Each applet type declares the content types it opens, and the router picks one applet per file by the rule "How a
  file type maps to an applet" settles
- The router hands each file to the chosen applet's source-taking entry point, the same one its open panel and drop
  use
- A file no applet declares is refused with a message that names the file and its type
- Routing works with fixture applets, so it needs no production viewer to test
- A routed pane's start directory follows "Start directory and current directory", with no implicit inheritance
- The "Open With" choice, if the type mapping keeps one, lists every applet that declares the file's type

### M2: Finder and Dock

**Status:** NOT STARTED

- Open With in Finder and a drop on the Dock icon open the file in uniterm, at launch and while running
- The app's declared document types match the applet declarations, and a test fails when they drift
- uniterm never becomes the default app for a type without the user choosing it
- Several files and folders follow the rules their open questions settle

### M3: File > Open

**Status:** NOT STARTED

- File > Open opens a panel and routes the chosen file, by the key ownership "Who owns Cmd-O" settles
- The panel starts in the directory "Start directory and current directory" settles
- A test checks that no built-in applet command claims the File > Open key, if it is reserved

### M4: The path-reading power

**Status:** NOT STARTED

- A controller command that makes an applet read a path is refused without the power, and with a path outside its
  scope
- A symlink or a rename between check and open cannot reach a file outside the scope
- Missing, unsupported, and denied paths outside the scope return the same error
- A pane whose source lies outside a controller's scope sends that controller no path or content from it
- Revoking the grant stops queued reads, per ADR-09
- A path outside the scope raises no macOS privacy prompt, and a FIFO or device path never blocks the pane
- Every file a folder source opens for a controller, such as a slideshow member, passes the same check, so a symlinked
  member cannot reach outside the scope
- Scope and path compare as APFS does, so case and Unicode normalization cannot widen or narrow the scope
- An older build refuses a stored approval that holds the path-reading power, and authorizes nothing from it

### M5: `uniterm open`

**Status:** NOT STARTED

- `uniterm open <path>` opens the path through the router, with the authority "Who may run `uniterm open`" settles
- The reply carries no file content
- An old `uniterm` command with a new app, or the reverse, is refused at the handshake

### M6: Terminal clicks

**Status:** NOT STARTED

- Cmd-click on a path or a local `file:` hyperlink in the terminal opens it through the router, with the authority
  and relative-path rule their open questions settle
- A `file:` hyperlink naming another host, and a path in an ssh session, never open a local file

## Decision Log

- 2026-11-03: Filed as a draft to meet UTERM-009's revisit hook before a second viewer among UTERM-006 to UTERM-008
  starts its first milestone. Settled only what UTERM-006 and UTERM-009 had already settled: the scope, one route, and
  the path-reading power's shape. Every other choice is an open question.
- 2026-11-03: Critique pass 1. Amended "The path-reading power" in two places. The scope check said only that it ran on
  the opened descriptor, after the open. An out-of-scope path was then opened before it was refused, which could raise
  a macOS privacy prompt under uniterm's name or block on a FIFO. A check of the canonical path now runs before the
  open, and the descriptor check stays. The user's-act rule said any app-level entry point needs no grant. That
  quietly settled `uniterm open` and terminal clicks, whose targets a program chooses, so it now names Finder, the
  Dock, File > Open, and in-pane opening only. Also narrowed the privacy rationale to controllers with no file access
  of their own, added UTERM-008's `pin selected` event to Impacts, put non-file URLs out of scope, added constraints
  on placement, relative and remote paths, and `uniterm open` replies, and routed five checks to M1 and M4.

## References

- [ADR-03](../adr/ADR-03-restored-state-never-runs-a-program.md): restored state is inert
- [ADR-06](../adr/ADR-06-layout-file-versioning-and-schema-ownership.md): each applet owns its payload
- [ADR-09](../adr/ADR-09-control-authority-requires-authenticated-identity-and-explicit-scope.md): control authority,
  separate powers, and explicit scope

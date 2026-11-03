# UTERM-015: Cross-Applet File Opening

**Status:** designing
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
- UTERM-008 — "Where pins come from": under "The path-reading power", a driver whose scope does not hold the user's
  file gets no value from it. UTERM-008 was amended so `pin selected` marks a file pin without its ID, and a click on
  one sends no `map clicked`
- UTERM-007 — "The applet contract": its "Open..." command with no key is the pane-local open "Who owns Cmd-O" settles.
  Its documents reach it through the router, and it declares the types it opens
- UTERM-006, UTERM-008, UTERM-009 — "Input sources": each declares a pane-local "Open..." command with no key, as
  UTERM-007 does, and the types it opens with a rank
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
- A file the user picks in File > Open, or in a pane's own open panel or drop, is the user's act, not a controller's.
  It needs no grant. Opens that arrive through Launch Services, `uniterm open`, and terminal clicks are not covered by
  this rule, since a program can choose what they name. Their own questions decide their authority. Amended
  2026-11-03; see Decision Log.

Rationale: UTERM-006 settled this shape in review, and the user kept it at the review gate. Without a scope, a script
with no file capability could probe which files exist, and borrow uniterm's macOS privacy grants for Downloads,
Documents, and Desktop. The scope protects controllers that have no file access of their own. A process uniterm
starts, such as a shell or an exec driver, already holds those grants directly, and the scope does not change that.
The grant's declaration and approval are open. See "How the path-reading power is granted".

### Which entry points open files

Original question: which app-level ways to open a file this proposal builds.

Decision: all of them. Finder Open With, a drop on the Dock icon, File > Open, a `uniterm open` command, and Cmd-click
on a path or a local `file:` hyperlink in the terminal.

- Terminal clicks need uniterm to handle libghostty's open-URL action. It reaches the app through an addition to the
  terminal surface protocol, per ADR-01, never as a libghostty type outside that module.
- A click on a web URL or any other non-file scheme does nothing new. Opening it in a browser is out of scope.
- Who may open by click is its own question, "Who may open by terminal click".
- `uniterm open` can be no stricter than the Launch Services path, per "Opens that arrive through Launch Services".

Rationale: the Motivation's user works at a terminal, and the common case is a file beside the terminal. Finder, the
Dock, and File > Open alone leave that case to the mouse. `uniterm open` covers paths the user types, and clicks cover
paths a program prints. Leaves undone: nothing.

### How a file type maps to an applet

Original question: several applets can read one type, such as `.json` for the data viewer and the text viewer, and
`.geojson` for the map, the data viewer, and the text viewer. How the router picks one.

Decision: each applet type declares the types it opens with a rank, an "Open With" choice overrides one open, and a
per-type choice the user saves overrides the rank.

- Each compiled applet type declares the content types it opens. Each declaration carries a rank from a fixed set:
  owner or alternate.
- Every declared type the system lacks is imported in `Info.plist` with its real conformance, such as `.geojson`
  conforming to `public.json`. Without it, the file resolves to a dynamic type that matches no declaration.
- One match is more specific than another when its declared type conforms to the other's. Rank decides only between
  matches that are equal or that neither conforms to. Two applets claiming the same type at the same rank fail a test,
  so no silent tiebreak ever picks a default.
- An "Open With" choice in uniterm lists every applet that declares the file's type. It can save the choice for the
  file's exact type, and the user can clear a saved choice.
- A saved choice matches the file's exact resolved type only, never types that conform to it. A choice for `.json`
  therefore never moves `.geojson` away from the map. When it names an applet type that no longer exists, or one that
  no longer declares the type, that open falls back to the rank, and the saved choice is kept for when it returns.
- Only the user's own UI writes a saved choice. No script or controller can write one, and only compiled applet types
  declare types.
- A new applet type declares its types beside its code. Its imported and document types still edit the host's
  `Info.plist`, which the drift test checks.

Rationale: users differ on `.json`. A developer reading config wants it as text, and an analyst wants an API dump as a
table. Picking "Open With" on every open is a standing chore for whichever one the rank does not suit, so the saved
choice has named users. A host table drifts from what each applet's entry point accepts. Asking on every open with
several claimants adds a second chooser after Finder's, and lets any program raise prompts with `open -a`.

### Who owns Cmd-O

Original question: whether Cmd-O belongs to the window, routed, or to each viewer, opening into its pane.

Decision: File > Open is a window command on Cmd-O, always through the router. Each viewer keeps a pane-local Open
command with no default key.

- Cmd-O is a reserved window key under UTERM-013, so it works the same in every pane, the terminal and the launcher
  included.
- The pane-local command replaces the pane's source. UTERM-007 already declares it, as "Open..." with no key. Each
  other viewer declares the same. It is reached from the applet menu and the palette, and the user can remap a key to
  it under UTERM-013.
- Replacing the source of a pane a controller owns is the user's act. That controller gets nothing outside its scope
  from it, per "The path-reading power".

Rationale: an applet-owned Cmd-O leaves the terminal and the launcher, the most common panes, with no keyboard open.
It also changes what Cmd-O does with focus, which UTERM-013's reserved keys exist to prevent. A window command alone
leaves the in-place replace off the palette.

### How the path-reading power is granted

Original question: how a controller gets the path-reading power, and the shape of its scope.

Decision: a typed permission in UTERM-004's set. Its scope is a list of directories, and protected locations inside a
scope directory are excluded unless the scope names them.

- A controller declares the power and its scope at startup. The user approves it through UTERM-004's panel, with
  Allow once, session, and remembered approvals as for every other power.
- The scope is a list of directories.
- A scope directory never covers a macOS-protected location inside it unless the scope names that location. One list
  of protected locations, kept in one place with a test, names Documents, Desktop, Downloads, iCloud Drive, other
  apps' containers, removable and network volumes, and the Photos library.
- Coverage compares effective scopes, with protected locations removed. A request for `~/Documents/x` is broader than
  an approved `~`, so it asks.
- The approval panel names every protected location a scope lies in or names.
- The read scope is its own type, not the directory scope of UTERM-004's host-launch grant. A launched process holds
  its macOS grants directly and needs no exclusion, so one shared type would mean two things in a stored approval.

Rationale: a per-path approval prompts once per slideshow member, and UTERM-004 forbids coalescing Allow once across
different operations, so prompts end in blind approval. One directory with no exclusion lets a scope of `~` silently
borrow uniterm's grants for Documents, which the power's settled rationale rules out. Comparing raw paths would cover
`~/Documents/x` under an approved `~` with no prompt.

## Design Decisions (Open)

### Where a routed pane goes

- **Beside the focused pane, as Split Right does.** In a new window when no window is open, such as an open from
  Finder at launch.
- **Into the focused pane when it is a launcher or an empty pane of the chosen type, else beside it.**
- **Finder and Dock opens in a new window, in-app opens beside the focused pane.** Matches how a document app behaves
  for a Finder open. Unless Launch Services opens are gated by sender, this covers every program-sent open too.
- Each option needs a rule for a split refused for lack of room. Candidates: a new window, a new tab in the window, or
  refusing with the "not enough room" message the window already posts.
- Each option needs a rule for a Finder open that arrives at launch while layout restore runs: whether the routed pane
  lands after restored windows, or in its own window.
- Constraint: a routed open never lands in a pane a controller owns. Otherwise a controller could place an empty pane
  to learn when the user opens a file.

### Which file types uniterm registers with Finder

Launch Services reads document types from the app's `Info.plist`, which cannot change at run time.

- **Register every declared type at the Alternate rank.** uniterm shows under Open With and never takes a default from
  another app. A test fails when the plist and the applet declarations disagree.
- **Register at the Default rank.** uniterm can become the default for types it registers. It can take a default
  quietly on install.
- **Register no document types.** Finder can still open a file by a drop on the Dock icon only if types are declared,
  so this rules out Finder and Dock opens.

### Opens that arrive through Launch Services

Finder Open With and a drop on the Dock icon reach uniterm as an open-documents Apple Event. Any process of the same
user can send the same event with `open -a uniterm <path>` or NSWorkspace. uniterm cannot tell those apart by the
event alone.

- **Accept them as the user's act, and say they are program-reachable.** ADR-09 disclaims isolation from same-user
  processes. The open returns nothing to the sender and never lands in a pane a controller owns. Leaves undone: a
  program can make uniterm open a file in a protected folder, and the user sees a pane they did not ask for.
- **Gate by the sender's audit token.** Only Finder and the Dock count as the user's act. Any other sender gets the
  authority "Who may run `uniterm open`" settles, or its own when that command is not built. Needs the sender's audit
  token from the Apple Event, which M2 must confirm macOS provides for this event. A program with Automation consent
  over Finder can still ask Finder to send the open, so "Finder as sender" means any process with that consent.
- **Ask before every Launch Services open from a sender that is not Finder or the Dock.** A local, coalesced approval
  like UTERM-004's pending indicator, with the sender named. M2 would then depend on UTERM-004 M6.
- Constraint: whatever authority "Who may run `uniterm open`" settles cannot usefully be stricter than this path. A
  program refused by `uniterm open` would otherwise run `open -a uniterm` instead.

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

### Who may open by terminal click

A Cmd-click is the user's gesture, but a program chose the target. An OSC 8 hyperlink's text can read `README.md`
while its target is `file:///Users/me/Documents/tax.pdf`.

- **A click is the user's act only when uniterm shows the resolved local target before the open.** uniterm handles
  libghostty's hover action and shows the target, and the click opens what was shown.
- **Hyperlinks follow the authority of `uniterm open`, and bare paths uniterm detects itself are the user's act.** A
  program chooses a hyperlink's target, and the user reads a bare path on screen.
- **Every click is the user's act.** Leaves undone: a program can make a click open a file the user did not read.
- Constraint: a click opens no more than the Launch Services path allows.

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
- **Draft applets change what they claim** — likelihood: medium, impact: low. UTERM-010 is a draft. Accepted:
  declarations live with each applet, so a later claim changes no router code, and an equal-rank claim fails a test.
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
- Working out a routed file's type never opens or blocks on a FIFO or a device node
- Routing works with fixture applets, so it needs no production viewer to test
- A routed pane's start directory follows "Start directory and current directory", with no implicit inheritance
- The "Open With" choice lists every applet that declares the file's type, can save the choice for the file's exact
  type, and lets the user clear it
- A saved choice for one type never routes a type that conforms to it, and a saved choice naming a missing applet, or
  one that no longer declares the type, falls back to the rank for that open
- No script or controller can write a saved choice
- A test fails when two applets claim the same type at the same rank, and when a declared type the system lacks is not
  imported with its conformance
- Type and placement work runs off the main thread, so a path on a slow network volume never stalls the UI

### M2: Finder and Dock

**Status:** NOT STARTED

- Open With in Finder and a drop on the Dock icon open the file in uniterm, at launch and while running
- An open sent by another program follows the authority "Opens that arrive through Launch Services" settles
- The reply to an open-documents event is the same for success, missing, unsupported, and denied
- The app's declared document types match the applet declarations, and a test fails when they drift
- uniterm never becomes the default app for a type without the user choosing it
- Several files and folders follow the rules their open questions settle

### M3: File > Open

**Status:** NOT STARTED

- File > Open opens a panel and routes the chosen file, by the key ownership "Who owns Cmd-O" settles
- The panel starts in the directory "Start directory and current directory" settles
- A test checks that no built-in applet command claims Cmd-O
- Each viewer's pane-local Open command replaces its source, and in a controller-owned pane that controller gets no
  path or content outside its scope

### M4: The path-reading power

**Status:** NOT STARTED

- A controller command that makes an applet read a path is refused without the power, and with a path outside its
  scope
- A symlink or a rename between check and open cannot reach a file outside the scope
- Missing, unsupported, and denied paths outside the scope return the same error
- A pane whose source lies outside a controller's scope sends that controller no path or content from it
- Revoking the grant stops queued reads, per ADR-09
- A path outside the scope raises no macOS privacy prompt, and a FIFO or device path never blocks the pane
- Canonicalizing stops at the first component outside the scope, and never stats or reads a link target outside it
- A dangling in-scope symlink to an outside target returns the same error as any other out-of-scope path
- Opening a device node has no side effect, such as a tty becoming the controlling terminal
- An in-scope symlink to an in-scope file opens through its canonical path, rather than failing on no-follow
- Every file a folder source opens for a controller, such as a slideshow member, passes the same check, so a symlinked
  member cannot reach outside the scope
- Scope and path compare as APFS does, so case and Unicode normalization cannot widen or narrow the scope
- An older build refuses a stored approval that holds the path-reading power, and authorizes nothing from it
- A request for a path under a protected location is not covered by an approved scope that only contains it
- The protected-location list has one owner and a test, and the approval panel names every protected location a scope
  lies in or names

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
- A Cmd-click on a web URL or another non-file scheme does nothing
- The open-URL action reaches the app through the terminal surface protocol

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
- 2026-11-03: Critique pass 2. Amended "The path-reading power" again. The user's-act rule still named Finder and the
  Dock, but any same-user process can send the same open with `open -a uniterm`, so the rule would have let a program
  skip whatever authority `uniterm open` gets. The rule now names File > Open and in-pane opening only. Launch
  Services opens became the open question "Opens that arrive through Launch Services". Routed four canonicalization
  and device checks to M4.
- 2026-11-03: Critique pass 3 converged. Added its constraints to "Which entry points open files", "Where a routed
  pane goes", and "Opens that arrive through Launch Services", and routed two checks to M1 and M2.
- 2026-11-03: Review start: 6 milestones, 3 settled decisions, 7 risks, no `**Live after:**` lines or row gates; five
  out-of-scope statements under "Scope"; proposal at the commit "Fold the converged critique's constraints into the
  open questions". The user asked for a design review of the 11 open questions, in autonomous mode.
- 2026-11-03: Which entry points open files: all of them, terminal clicks included. Who may open by click became its
  own open question. Converged in 1 pass. (autonomous)
- 2026-11-03: How a file type maps to an applet: applet declarations with an owner or alternate rank, "Open With"
  for one open, and a per-type choice the user saves, matched on the exact type. Equal-rank claims fail a test, and
  every claimed type is imported with its conformance. Converged in 2 passes, after the critic named the users a saved
  choice serves. (autonomous)
- 2026-11-03: Who owns Cmd-O: File > Open is a window command on Cmd-O through the router, and each viewer keeps a
  pane-local "Open..." with no key, as UTERM-007 already declares. Converged in 1 pass. (autonomous)
- 2026-11-03: How the path-reading power is granted: a typed UTERM-004 permission, its own scope type, a list of
  directories, with protected locations excluded unless named and coverage compared on effective scopes. Converged in
  1 pass. (autonomous)
- 2026-11-03: Updated for UTERM-007's acceptance: its "Open..." command is the pane-local open, and the risk about draft
  applets names only UTERM-010. ADR impact review: the settled text conflicts with no ADR. Routed ADR-08's main-thread
  bound to M1, and ADR-01's terminal surface protocol to M6. (autonomous)

## References

- [ADR-03](../adr/ADR-03-restored-state-never-runs-a-program.md): restored state is inert
- [ADR-06](../adr/ADR-06-layout-file-versioning-and-schema-ownership.md): each applet owns its payload
- [ADR-09](../adr/ADR-09-control-authority-requires-authenticated-identity-and-explicit-scope.md): control authority,
  separate powers, and explicit scope

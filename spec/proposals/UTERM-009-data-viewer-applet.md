# UTERM-009: Data Viewer Applet

**Status:** accepted
**Created:** 2026-10-31
**Updated:** 2026-11-03

## Dependencies

- UTERM-001
- UTERM-013, and UTERM-002's command registry milestone: M3's search commands are registry entries the applet declares

## Impacts

- UTERM-003 — "Input sources": the source-taking entry point is where "send data to an applet" lands for this applet
- UTERM-004 — "Input sources": pipe input waits on caller identification and the exec wire format

## Summary

A table viewer applet for CSV, JSON, and spreadsheet data. It supports filtering, sorting, and searching.

## Motivation

Tabular output is hard to read in a terminal. A table pane lets the user sort and filter it without leaving uniterm.

## Design Decisions (Settled)

### Table first

The applet shows data as a table. It supports filtering, sorting, and searching.

### Charts are out of scope

Charts and graphs are not part of this proposal. The write-up flags them as complex. A later proposal may add them.

### Input sources

Original question: whether data can arrive from a script or a pipe, as well as from a file.

Decision: files open from inside the pane now. Pipe and script input is deferred to UTERM-003 and UTERM-004.

- The pane starts from the launcher like any applet, so the applet factory does not change. Inside it, the user opens
  a file with an open panel or by dropping a file onto the pane. A drop accepts file URLs only.
- A pane shows one file. Opening another file replaces it: the old load is cancelled, and the new file starts with no
  sort or filter. The open panel selects one file. A drop of several files is refused with a message asking for one
  file, and the pane keeps what it showed. Amended 2026-11-03; see Decision Log.
- A drawer of open documents beside the table, as Preview has, is an idea for later. This proposal does not commit to
  it. Building it needs its own proposal, since it changes what a pane and its description hold.
- All loading goes through one internal entry point that takes a source. Today the only source is a file URL. A
  byte-stream source is added when its first caller lands. It spools to a file when a format needs random access, as
  `.xlsx` does.
- App-level opening is not part of this proposal. That covers Finder "Open With", document types, routing a file type
  to an applet, and which applet owns Cmd-O. UTERM-006, UTERM-007, and UTERM-008 open files too, and UTERM-013 owns
  shortcut ownership, so one cross-applet proposal decides it. The data viewer binds no File > Open shortcut until
  then.
- Pipe and script input waits on UTERM-003's "send data to an applet" host function and on UTERM-004's caller
  identification and exec wire format.

**Revisit:** when UTERM-003 settles how a caller reaches the app and UTERM-004 settles caller identification, decide
the byte-stream source, what a restored pane shows for data that had no file, and how a pipe reaches a pane; and file
the cross-applet file-opening proposal before a second viewer applet among UTERM-006 to UTERM-008 starts its first
milestone.

Rationale: a pipe into a pane beside the calling terminal is the complete answer to the Motivation. It needs caller
identity and a channel, which UTERM-003 and UTERM-004 have not settled. A launcher source that runs a command was
weighed. Modeled on terminal program mode, it splits the line into words with no shell, so it refuses
`kubectl get pods -o json | jq .items`. Running it through a shell would add a second command language beside program
mode, and a second path from program to pane beside UTERM-004's exec. Deciding app-level opening here would change the
factory every applet implements, from one consumer. Left undone: until those proposals land, command output needs a
redirect to a file first.

### Spreadsheet formats

Original question: macOS has no built-in reader for Excel files. Support `.xlsx` through a Swift library such as
CoreXLSX, skip spreadsheets at first, or also support legacy `.xls` through a separate library.

Decision: read `.xlsx` with an in-house OOXML reader on ZIPFoundation. Legacy `.xls` is not supported.

- ZIPFoundation (MIT) reads the ZIP container. It is the project's first third-party Swift package. It is pinned to an
  exact version, its `Package.resolved` is committed, and its notice joins `Licenses/` through the collect script.
- The project owns the OOXML layer, on Foundation's event-driven `XMLParser`, so rows stream instead of loading a whole
  sheet tree. It reads shared strings, inline and rich-text strings, cell values placed by cell reference, cached
  formula results, date number formats with `date1904`, and sheet paths through `workbook.xml.rels`. Multiple sheets
  get a sheet picker.
- Nothing is evaluated. A formula with no cached value shows as empty, marked as not computed.
- `.xlsm` opens with its macros ignored. `.xls`, `.xlsb`, and password-protected files each show a message that names
  the format, never "corrupt".

Rationale: streaming rows fits the large files decision. CoreXLSX decodes each sheet into a full in-memory tree through
XMLCoder, brings three packages, and last shipped in March 2023. A fully in-house reader would make the project own
untrusted ZIP parsing, including ZIP64 and data descriptors, with no gain in correctness. The format logic the project
must get right either way, such as dates, stays in-house. libxls, the usual `.xls` reader, is C with a history of
memory-safety CVEs, maintained outside the OS, and would parse untrusted files in-process with the App Sandbox off.
The chosen reader still reaches C through libxml2 and zlib, but those are OS libraries that macOS updates patch. See
Risks. The Summary names spreadsheets, not `.xls`.

### JSON shapes

Original question: how JSON maps to a table. An array of flat objects is easy. Nested objects and arrays need a rule:
flatten, show as expandable cells, or reject.

Decision: flatten nested objects into columns, and show arrays as cells that open a nested table.

- Nested objects become columns named by their path, such as `user.login`. Arrays, and nesting past the flattened
  paths, show as cells that open a nested table on demand.
- A column's identity is its path as a list of key segments, not a dotted string. A dot inside a key is escaped only
  when the name is shown. So `{"a.b": 1, "a": {"b": 2}}` gives two columns. The sort state in the
  description names columns by that identity, as "The applet contract" refines it for repeated names.
- Every top-level shape opens as a table: an array of objects (columns are the union of keys, in first-seen order), an
  array of scalars (one column), an array of arrays (positional columns), a single object (key and value columns), and
  JSON Lines.
- A missing key and an explicit `null` display differently.
- Numbers display their original text, so a large integer or a long decimal is never rounded.

Rationale: common API fields become columns the user can sort and filter, and array contents stay tables instead of
text. Rejecting nested JSON would fail on most API output. Naming columns by segment list keeps two different values
from sharing a column, and fixes the stored sort and filter state before the payload format ships.

### Large files

Original question: a size limit, or streaming rows for large files. Whether sorting and filtering run off the main
thread.

Decision: rows stream off the main thread into memory, under one memory budget.

- Parsing runs off the main thread. Rows appear as they arrive, a status bar segment shows progress, and close cancels
  the load.
- Rows live in a compact in-memory store. The loaded rows are a snapshot, so a later change to the file cannot corrupt
  the view.
- One memory budget covers every data viewer pane together, and a memory-pressure warning stops loading early. When
  loading stops, the pane says it shows the first N rows of the file.
- Sorting, filtering, and search run off the main thread on an immutable snapshot. A newer request cancels an older
  one, and results swap in when done.
- Loading is not running work. Reopen and relaunch read the file again, so closing a loading pane does not ask.

Rationale: one storage model works for every format, and once the load is done, nothing reads the file from the main
thread. A shared budget bounds the app, not just one pane, so a huge file cannot get uniterm killed along with its
terminals. Indexing a CSV file by row offset in a memory-mapped file was weighed. Rewriting the file in place, as
`cmd > out.csv` does, raises SIGBUS on a page past the new end, which crashes the app. Page faults on a stalled mount
block the main thread. And the offset index and sort permutation still need a budget for a file with hundreds of
millions of rows. A disk-backed row store for every format would let every row be viewed, but it copies a file as large
as the source to disk, and no one has asked to view every row of a multi-gigabyte file. Left undone: rows past the
budget cannot be viewed, and sort, filter, and search cover only the loaded rows.

### The applet contract

Original context and question: Context from UTERM-001, which shipped the applet contract. ADR-05 and ADR-06 cover its lifecycle and its description
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

For the data viewer: a description likely holds the source file and the sort and filter state. When the data came from
a command's output, restoring must not run that command again.

Decision: the data viewer needs no change to the applet contract or the factory, beyond what UTERM-013 already makes.
Its description holds a path, a bookmark fallback, a start directory, and the view state, and never any data from the
file.

- Per UTERM-013, the data viewer declares its own commands in UTERM-002's registry: Find (Cmd-F), Find Next (Cmd-G),
  Find Previous (Cmd-Shift-G), and Focus Filter with no key. The filter field and the open panel need no key. The data
  viewer has no tabs, so its description has no undo-only part. Cmd-Shift-T reopens a closed data viewer pane from its
  description.

- The payload holds the file's absolute path, a macOS bookmark of the file, the selected `.xlsx` sheet, the sort as a
  column identity and a direction, and the filter text. It has its own version, per ADR-06.
- Restore opens the stored path when a regular file is there. It uses the bookmark only when the path is missing, and
  then says where it found the file. A file renamed away and replaced by a new one at the same path shows the new one.
- Every description, the empty one included, holds the directory the pane started in. The factory passes it. An empty
  pane reports it as `currentDirectory`. With a file open, the pane reports the file's folder. The open panel always
  starts in `currentDirectory`. The open panel's own remembered directory is never used, since it is AppKit state, not
  the pane's.
- A column's identity is its key-segment list plus its occurrence among columns with the same name. A headerless CSV
  column, or an `.xlsx` column with no header, is named by its position. So two `amount` headers stay two columns, and
  a restored sort lands on the right one.
- The bookmark is created at load, and remade when an open, a restore included, finds a different file than the
  bookmark names. Resolution runs in `start()`, off the main thread, without UI and without mounting volumes.
  `describe()` never touches the disk. Amended 2026-11-03; see Decision Log.

Rationale: the path is what the user named, so it wins while a file is there. The bookmark recovers a file that was
moved or renamed. Bookmark-first resolution follows the file ID, which would show a rotated-away backup instead of the
fresh file. The launcher's `directory` and the terminal's `startDirectory` already carry the start directory
explicitly, and the data viewer follows them. Storing the rows in the description would contradict the large files
decision, write file contents that may hold secrets into the layout file, and make ADR-06 keep them byte-for-byte in an
older build. A size and modification-time marker was weighed. A dropped sort or filter is the confusion it targets, and
M1 already drops those per column. Equal size and time also do not prove a file is unchanged.

## Design Decisions (Open)

None.

## Risks

- **A huge file freezes the pane** — likelihood: medium, impact: medium.
  Mitigation: the large files decision parses, sorts, and filters off the main thread, under a shared memory budget.
- **A hostile file corrupts or takes over the app** — likelihood: medium, impact: high. The readers parse files from
  Downloads or email in uniterm's own process, with the App Sandbox off by design. The CSV, JSON, and OOXML logic is
  Swift, where a bug traps and ends every terminal pane's shell with the app. Under `.xlsx`, the bytes also pass through
  C: Foundation's `XMLParser` wraps libxml2, and inflation runs in the Compression framework or zlib. A bug there can
  corrupt memory silently, or run code with the user's privileges. The evidence does not settle the likelihood, so it
  is rated the higher of low and medium. Mitigation: libxml2 and zlib are OS libraries that macOS updates patch. M2 and
  M4 cap nesting depth, inflated bytes, and the shared strings table, and turn off external XML entities. Each reader's
  milestone fuzzes the parsing stack as shipped under a memory-error detector. This is the same exposure for which
  libxls was rejected, made smaller by OS maintenance and the caps, not removed. Moving parsing into a sandboxed helper
  process would remove it, and would add a helper target and a sandbox profile. **Revisit:** when fuzzing finds a
  memory error or a crash the caps do not prevent, or an advisory in a libxml2 or zlib path that `XMLParser` or
  inflation reaches is unpatched on a macOS version uniterm supports, file a proposal to move parsing into a sandboxed helper process.
- **The first third-party Swift package** — likelihood: low, impact: medium. ZIPFoundation brings a supply-chain path, a
  SwiftPM fetch in the build, and license collection that the build does not do yet. Mitigation: M4 pins it exactly,
  commits `Package.resolved`, collects its license, and settles the offline-build check's scope.
- **UTERM-002 and UTERM-013 are accepted but not built** — likelihood: medium, impact: low. If the command registry's
  shape shifts while it is built, M3's commands change with it. Mitigation: M3 depends on UTERM-002's registry
  milestone and starts after it.
- **Pipe input's restore rule is still open** — likelihood: medium, impact: low. When UTERM-003 and UTERM-004 settle,
  data that had no file may need a new payload field. Accepted: ADR-06's payload versioning makes that a version bump,
  and an older build keeps the newer description byte-for-byte.
- **The description is stored data** — the payload format is read by every later build. The design defuses the one-way
  door: the payload carries its own version per ADR-06, and an unreadable description is kept, not dropped.

## Milestones

### M1: CSV table

**Status:** NOT STARTED

- A pane can run the data viewer and open a CSV file as a table, from an open panel or by dropping a file on the pane
- Every load goes through the one source-taking entry point
- A drop accepts file URLs only, and the data viewer binds no File > Open shortcut
- Opening a file into a pane that shows one replaces it, cancels any load still running, and clears the sort and
  filter. A drop of several files is refused with a message asking for one file, and the pane keeps what it showed
- The loader opens regular files only, so a FIFO, a device, or a stalled mount never blocks the pane, and reads off the
  main thread
- A missing or unreadable file shows a message in the pane. Stored sort and filter state that names an absent column
  is dropped, not an error, and only once loading has finished or stopped at the budget
- A file larger than the memory budget opens its first rows and keeps the "first N rows" notice visible while sorted,
  filtered, or searched. Counts read "X of the first N rows"
- Under an active sort or filter, rows that arrive while loading never show out of order
- Closing a pane mid-load frees its memory promptly, and closing it never asks
- The budget counts every row the panes hold, across all data viewer panes, and a memory-pressure warning stops loading
- Reopen and relaunch bring back the file with its sort and filter, and an empty pane reopens empty in its start
  directory. Reopen works through whichever key reopens a pane when M1 lands, and through Cmd-Shift-T once UTERM-013 M2
  lands
- A file moved or renamed after the save is found through its bookmark, and the pane says where. A new file at the
  stored path wins over the bookmark, and the bookmark is then remade for it
- The open panel starts in the pane's `currentDirectory`, never in the panel's remembered one. When the file's folder
  is gone, `currentDirectory` is the start directory, or nil when that is gone too
- A restored file in a folder behind macOS privacy protection, such as Downloads, shows a permission message when access
  is denied, not "missing" or "corrupt"
- A layout save never touches the disk to describe a pane, and an unchanged pane describes itself the same way twice
- Two columns with the same header keep separate identities, and a restored sort lands on the right one
- The launcher offers the data viewer, and restore picks the applet by description type. An unknown type still
  becomes a placeholder pane
- While the bookmark is still resolving, `describe()` returns the restored payload unchanged. Once the bookmark finds a
  moved file, the stored path becomes the new one
- The payload carries the sheet field from its first version, so M4 needs no version bump
- A pane that opens while other panes hold the whole budget still loads a minimum of rows, or says why it shows none.
  Restored panes share the budget the same way at every launch
- A fuzzing run with malformed CSV input, non-UTF-8 encodings included, through the parsing stack as shipped and under a memory-error detector,
  finds no crash and no memory error
- One documented rule picks a CSV file's header row, delimiter, and text encoding, and gives the same answer for the
  same file
- Clicking a column header sorts by that column
- A filter field hides rows that do not match

### M2: JSON

**Status:** NOT STARTED

- An array of JSON objects opens as a table, one column per flattened key path
- Nested values follow the settled JSON shapes rule
- An object used as a map keyed by data, such as thousands of IDs as keys, becomes an expandable cell instead of
  thousands of columns
- Deeply nested input shows an error instead of crashing, and a top-level scalar or an empty array opens with a message
- A key that holds an object in some rows and a scalar or an array in others still shows every value
- Duplicate keys in one object follow one documented rule, and JSON Lines is told apart from a single JSON value
- Sorting a column with mixed types, `null`, and missing values follows one defined order
- The JSON reader is Swift, not `JSONSerialization`, so the large files and number-text rules hold
- A fuzzing run with malformed JSON input, through the parsing stack as shipped and under a memory-error detector,
  finds no crash and no memory error
- A large top-level array of objects streams within the memory budget, without parsing the whole document first

### M3: Search

**Status:** NOT STARTED

- Searching highlights matching cells and steps between them
- Find, Find Next, Find Previous, and Focus Filter are registry commands the data viewer declares, with menu items, and
  none of their keys is a reserved window key
- The Find items sit in Edit > Find, work while focus is in the filter field, and are disabled when no file is loaded

### M4: Spreadsheets

**Status:** NOT STARTED

- An `.xlsx` file opens as a table, and a workbook with several sheets offers a sheet picker
- Dates show as dates, under both the 1900 and the 1904 date systems, including Excel's serial 60
- Shared, inline, and rich-text strings show their text, and sparse cells land in the column their reference names
- A formula with no cached value shows as not computed
- A fuzzing run with malformed `.xlsx` input, through the parsing stack as shipped and under a memory-error detector,
  finds no crash and no memory error
- A file whose inflated entries pass a size cap stops with a message. The cap counts bytes actually inflated, not the
  sizes the archive claims, and the shared strings table has its own cap
- Rows stream: peak memory on a large sheet stays bounded, and the reader never buffers a whole sheet entry first
- External XML entities are off, and entity expansion is bounded
- `.xls`, `.xlsb`, and password-protected files each show a message naming the format; `.xlsm` opens
- The selected sheet survives reopen and relaunch
- ZIPFoundation is pinned exactly, `Package.resolved` is committed, its license notice is collected, and the
  offline-build check either covers SwiftPM fetches or states that it covers Ghostty only

## Decision Log

- 2026-10-31: Drafted from the original write-up without an interview. The open questions hold everything undecided.
- 2026-11-01: Added "The applet contract" with context from UTERM-001's implementation.
- 2026-11-02: Review start: 3 milestones, 2 settled decisions, 1 risk, no `**Live after:**` lines or row gates; one
  out-of-scope statement (charts); proposal at commit 8c5291d. The user asked for a design review of the open
  questions, in autonomous mode.
- 2026-11-02: JSON shapes: flatten nested objects into columns named by key-segment paths, and open arrays as nested
  tables. Every top-level shape opens. (autonomous)
- 2026-11-02: Spreadsheet formats: `.xlsx` through an in-house streaming OOXML reader on ZIPFoundation, the project's
  first third-party Swift package. No `.xls`. Added M4 for spreadsheets. (autonomous, addition: the first
  third-party package and the pinning and license-collection policy it brings)
- 2026-11-02: Input sources: in-pane file opening through one source-taking entry point; pipe and script input deferred
  to UTERM-003 and UTERM-004, and app-level file opening to a cross-applet proposal to be filed, both under the
  settled entry's revisit hook. The judge ruled after the critic's top choice moved to a launcher command source and
  back. (autonomous, judge, addition: the commitment to file a cross-applet file-opening proposal)
- 2026-11-02: Large files: rows stream off the main thread into memory under one budget shared by every data viewer
  pane, with a "first N rows" notice. Sort, filter, and search run off the main thread. (autonomous)
- 2026-11-02: The applet contract: no contract change. The description holds a path with a bookmark fallback, an
  explicit start directory in every state, the sheet, and the sort and filter by occurrence-qualified column identity.
  It never stores file data. The open panel's remembered directory is replaced by the explicit start directory.
  (autonomous)
- 2026-11-02: Coherence review. Amended "The applet contract": the open panel starts in `currentDirectory`, not always
  the start directory. Before, a pane with a file open sent its panel back to the start directory, while a split from
  it started in the file's folder. Added the data viewer's registry commands per UTERM-013, a dependency on UTERM-013
  and UTERM-002's registry milestone, and "reopen" wording in place of "undo". (autonomous)
- 2026-11-02: Risk review. Added risks for parsing untrusted files in-process, the first third-party package, the
  unbuilt registry, and the open pipe-restore rule, and noted the description's one-way door. Mitigated the crash risk
  with caps and fuzzing in M1, M2, and M4, rather than a sandboxed parser process. (autonomous)
- 2026-11-02: Re-check. Restated the untrusted-file risk: `.xlsx` parsing reaches C through libxml2 and zlib, so the
  worst case is memory corruption or code execution, not a trap. Mitigated by OS-patched libraries, the caps, and
  fuzzing under a memory-error detector. A sandboxed helper waits on the risk's revisit hook. (autonomous)
- 2026-11-02: Review gate: kept all. The user chose the open panel's explicit `currentDirectory` over AppKit's
  remembered folder, as CLAUDE.md asks for hidden state flow.
- 2026-11-02: ADR candidate (cuts across the system): untrusted files are parsed in-process only through Swift and
  OS-maintained C libraries, and a third-party C parser is rejected. Waits on M4's fuzzing results and the
  untrusted-file risk's revisit hook, either of which may move parsing into a sandboxed helper.
- 2026-11-02: ADR candidate (cuts across the system): every third-party Swift package is pinned to an exact version,
  with `Package.resolved` committed and its license collected. Waits on M4, which settles whether the offline-build
  check covers SwiftPM fetches.
- 2026-11-02: Accepted by the user after the review.
- 2026-11-03: Amended "The applet contract": the bookmark is remade when an open finds a different file than the
  bookmark names. Before, it was created once at load and refreshed only when resolution reported it stale. So after
  a renderer rotated `render.png` away and wrote a new one, the path won on restore but the bookmark still named the
  rotated-away file. Once the new file was renamed, the next restore followed the bookmark to the stale file. Found in
  the UTERM-006 review, which settles the same rule. The marker on the `currentDirectory` bullet moved here, since a
  decision carries one marker; the 2026-11-02 entry above still records that change.
- 2026-11-03: Amended "Input sources": a pane shows one file, opening another replaces it, and a drop of several files
  is refused with a message asking for one. Before, the decision said nothing about either case. Noted a Preview-style
  document drawer as an idea that needs its own proposal. The user's decision.
- 2026-11-03: Scheduled as UTERM-009 M1-M4 in queue.md.

## References

- Original write-up: `~/projects/private_specs/uniterm/spec/research/original-writeup.md`, APPLET-4

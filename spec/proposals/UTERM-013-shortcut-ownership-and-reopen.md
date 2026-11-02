# UTERM-013: Shortcut Ownership and Reopening Closed Tabs

**Status:** accepted
**Created:** 2026-11-01
**Updated:** 2026-11-01

## Dependencies

- UTERM-001
- UTERM-002: its command registry milestone

## Impacts

- UTERM-001 — "Whether uniterm reads the user's Ghostty config": every binding is a uniterm menu item today. This
  proposal moves applet actions to the applet.
- UTERM-001 — "What undo close restores": Cmd-Z no longer reopens panes, and a description gains an undo-only part
- UTERM-002 — "Hotkey default" and "Command source": the palette's key is a reserved window key, and applet commands
  are registry entries. This proposal narrows "every uniterm binding runs a registry command" to leave out the standard
  edit actions, which stay on the responder chain. UTERM-002's text needs the same narrowing.
- UTERM-005 through UTERM-010 — "The applet contract": each applet declares its own key bindings and menu items, and
  may carry an undo-only description part
- ADR-04 — rewritten in place for the window-versus-applet key rule
- ADR-05 — a tab reopen follows the same "reopen from the description" rule as a pane

## Summary

uniterm binds only window-level shortcuts and the standard edit keys. Each applet declares the shortcuts for its own
actions, such as tabs, text size, and clearing. Cmd-Shift-T reopens what was closed most recently in the window, a tab
or a pane. Cmd-Z goes back to undoing text edits only.

## Motivation

The user walked through the built app and found three problems.

- Cmd-Z for reopening a pane feels wrong. Browsers and editors use Cmd-Shift-T to reopen what was just closed.
- A closed terminal tab cannot be reopened. Applets own their tabs, so they should own reopening them too.
- uniterm binds terminal-only actions, such as Clear Screen on Cmd-K, as window shortcuts. Those belong to the
  terminal. uniterm should bind only what works across applets. A window key added later, such as the palette's,
  then has a clear rule for which keys it may take.

## Design Decisions (Settled)

### uniterm binds window-level shortcuts, and applets bind their own

uniterm binds the shortcuts that act on the app, a window, or the pane tree. They include settings, hide and quit, a
new window, splits, closing a pane, pane focus, the message history, and reopening. Each applet declares the
shortcuts for its own actions. The terminal declares new tab, tab selection, text size, and clear. Amended 2026-11-01;
see Decision Log.

The standard edit actions are the exception. Cut, Copy, Paste, Select All, Undo, and Redo stay uniterm's fixed Edit menu
items, sent to whatever view has focus. The terminal implements copy, paste, and select all, and its view answers them
the way a text field does. uniterm keeps the items, so the launcher's fields and the Settings rows keep working.

uniterm still clears libghostty's built-in bindings, as ADR-04 requires, so no key reaches libghostty's own handling.

Chosen by the user on 2026-11-01.

### Applets own their tabs, and reopening them

An applet with tabs keeps its own list of closed tabs, as descriptions. uniterm keeps no copy. Each applet reports the
stamps of its closed tabs, newest first. uniterm asks the owning applet to reopen a tab by its stamp, and the applet
reports whether it succeeded. Amended 2026-11-01; see Decision Log.

Chosen by the user on 2026-11-01.

### Cmd-Shift-T reopens, and Cmd-Z undoes text edits only

Cmd-Shift-T reopens the newest close in the window, whether a tab or a pane. Amended 2026-11-01; see Decision Log.
Cmd-Z undoes edits in a focused text field and nothing else.

- Each applet stamps every closed tab with a counter value the host issues. Pane closes take their stamp from the same
  counter.
- On Cmd-Shift-T, uniterm walks the window's closes newest first, across every applet's closed-tab stamps and the
  pane closes. It reopens the first that succeeds, and a reopened tab's pane takes focus.
- An applet's reopen of a tab, named by its stamp, reports whether it succeeded.
- A close that fails to reopen, such as a pane that does not fit or a tab whose session fails to start, keeps its stamp
  and its place. The next press tries it first again. One status message names what failed, why, what to do, and what
  reopened instead.

Rationale: closing a pane moves focus to a neighbor. Under a focused-pane rule, a neighbor with a closed tab would take
Cmd-Shift-T, and the pane would come back only after that neighbor's list was empty. Browsers reopen the newest close
in the window. A query keeps one copy of each list, in its applet. A host copy would drift: a reopened pane gets a new
ID, and the host and the applet would trim at different depths.

Chosen by the user on 2026-11-01.

### Where an applet's shortcuts appear in the menu bar

Original question: menu items in an applet menu that appears while the applet has focus, or items merged into the
standard menus.

Decision: each applet item names its own home. The standard edit actions stay fixed uniterm items, per the first
settled decision.

- An item with a macOS home goes there. Text size goes in View, and New Tab goes in File. Close is uniterm's, per the
  Cmd-W decision. Amended 2026-11-01; see Decision Log.
- An item with no standard home, such as Clear, goes in an applet menu named for the applet type. That menu appears only
  while the focused applet has such items.
- The menus follow the key window's focused pane. When Settings or a sheet is key, applet items are disabled.
- The Edit menu gains Cut and Redo, which it lacks today, so Cmd-X and Cmd-Shift-Z work in text fields.

Rationale: this follows the macOS layout, so Copy is in Edit and text size is in View. Applet menus merged in by focus
would remove Edit > Paste whenever a non-terminal view has focus. The launcher's filter and command fields and the
Settings rows are NSTextFields, and they paste only through those items. A single applet menu moves Copy out of Edit,
and keys an applet view handles itself cannot be checked against the reserved set.

### What one shortcut declaration is

Original question: whether a declaration is a key plus a selector, or a richer command that the palette can also list
(UTERM-002).

Decision: a command in UTERM-002's command registry. The standard edit actions are not commands. They stay on the
responder chain. Amended 2026-11-01; see Decision Log.

- The registry is UTERM-002's, built by its registry milestone. An entry is owned by uniterm, for a window command, or
  by an applet type, for an applet command.
- A command has a stable ID namespaced by its owner, such as `terminal.clear`. An ID is never reused for a different
  action.
- It has UTERM-002's shape: a title, an availability check, and a synchronous run action that may start UI or a task
  and return. That work must not keep the applet alive past close.
- This proposal adds an optional default key and a menu home to each entry.
- uniterm builds the menus from the registry: its own commands and the focused applet's. The palette lists the same
  commands.

Rationale: when the palette has focus and runs a command, a selector sent to the first responder reaches the palette
field, not the applet. A command calls the applet directly. A stable ID gives the palette, and any later caller, a name
that survives a title change. Copy and Paste stay on the responder chain because a command would call the applet, not
the focused subview, such as a browser's address bar or a find field.

This follows UTERM-002's accepted "Command source", with one narrowing. UTERM-002 moves every UTERM-001 binding onto
the registry. Here the standard edit actions stay on the responder chain, since a registry command would act on the
pane, not on a find field or address bar inside it. It also fills the gap that decision left undone: menus now read the
registry. A Janet API calling commands by ID stays with UTERM-003.

### Who decides what Cmd-W closes

Original question: Cmd-W closes a tab first, then the pane at the last tab. Decide whether the applet or uniterm owns
that choice.

Decision: uniterm owns Cmd-W and asks the focused applet to close its current tab.

- Cmd-W is one File item with the fixed title "Close". Its title does not change with the tab count. Amended
  2026-11-01; see Decision Log.
- The palette's close command runs the same registry action.
- The applet answers closed, declined, or nothing to close.
- Only "nothing to close" leads uniterm to close the pane. The pane close guard applies as usual.
- An applet without tabs always answers "nothing to close".

Rationale: one owner keeps Cmd-W a window key in every applet, so the pane close guard always runs. It mirrors the
settled reopen rule, where uniterm asks the applet to reopen a tab. Today's tab close returns one Bool for both a
decline and the last tab. Built on that, declining a tab close at the last tab would close the pane. App Shortcuts
remaps match a menu item by its title, so a title that switched between Close Tab and Close Pane would lose a remap
whenever the tab count changed. UTERM-002 already names the item "File > Close".

### How long an applet's closed-tab list is, and whether it outlives the applet

Original question: how long an applet's closed-tab list is, and whether it survives a relaunch in the applet's
description.

Decision: the list rides in an undo-only part of the applet description, bounded by a fixed policy depth.

- The layout file never writes the undo-only part, the same way it never writes the description's verbatim bytes.
- Pane undo carries it, so a reopened pane brings back its closed tabs.
- It is dropped at quit, like the pane undo stack. The terminal payload's saved format does not change.
- The depth is a policy value with no setting, like the pane undo stack's depth.

Rationale: closing tab B and then its pane, then reopening the pane, should let a second Cmd-Shift-T bring back B. ADR-05
says an applet saves in its description what undo should restore. Saving the list with the layout would bring closed
tabs back after a relaunch while closed panes stay gone. It would also write the closed tabs' working directories to
disk.

### Whether Cmd-Shift-T with no closed tab falls through

Original question: whether Cmd-Shift-T in a pane with no closed tabs falls through to reopening a pane, or does
nothing.

Decision: it falls through to the last closed pane. The third settled decision already says so. Amended 2026-11-01;
see Decision Log. Under window-wide recency, a pane reopens whenever no closed tab in the window is newer.

### Which keys uniterm reserves

Original question: which keys uniterm reserves, so no applet can claim them. The palette's key is one.

Decision: the reserved set has three parts, and the window enforces it before any view sees a key. Amended
2026-11-01; see Decision Log.

- uniterm's window command keys, read from the live menu after the user's App Shortcuts remaps apply. A remapped
  uniterm item takes its reservation with it.
- The fixed Edit keys: Cmd-X, Cmd-C, Cmd-V, Cmd-A, Cmd-Z, and Cmd-Shift-Z.
- The keys AppKit adds to uniterm's menus itself, such as the window list and Enter Full Screen.
- The window routes a reserved key to the menu before the view hierarchy is asked. An applet view, or web content
  inside one, cannot take it.
- A new window key, such as the palette's Cmd-Shift-P from UTERM-002, joins the set when its command does.
- The set guards declared default keys only. A user's remap always wins, over uniterm's defaults and applets' alike.
  When a remap puts two items on one key, uniterm picks the remapped item itself, not AppKit's menu order.
- Cmd-1 to Cmd-9 are not reserved, since tab selection moves to the terminal. The launcher keeps them.

Rationale: AppKit asks the key window's views before the main menu, which the launcher relies on today. A check at
declaration time alone would let any applet view take Cmd-W or the palette key. Without the Edit keys in the set, an
applet command on Cmd-V in File would beat Paste by menu order, since File comes before Edit. A list of keys held for
features nobody has designed would be a guess. The built-in conflict test already fails the day a new window key lands
on an applet's key. UTERM-002 requires a remapped palette key to win even with a terminal focused. A static table would
leave a remapped key without early routing, so web content could take it.

### What happens on a key conflict

Original question: what happens when an applet declares a reserved key: a load error, a warning, or a silent loss.

Decision: the key is dropped, the user is told, and a test catches built-in conflicts.

- A command that declares a reserved key registers without its key. Its menu item and palette entry still work.
- When two commands of one applet declare the same key, both lose it.
- uniterm posts one status bar warning per applet type per session. It names the applet, the command, and the key, and
  says what to do next.
- Keys are compared in a canonical form, so Cmd-} and Cmd-Shift-] match.
- A unit test checks every built-in applet's commands against the reserved set and against each other.

Rationale: a load error would cost the whole applet for one key. A user's App Shortcuts remap, or a new window key, could then
turn every terminal pane into a placeholder at launch. A silent loss, or one written only to the system log, breaks the rule
that every failure is visible to the user.

### Where a reopened tab starts, and where it goes

Original question: a closed tab running something: the tab-close guard already asks. Decide whether the reopen
restores the tab's working directory the same way a pane reopen does.

Decision: a reopened tab follows the pane rule and returns to its former place.

- It starts a fresh shell from the closed tab's description. It uses the last OSC 7 directory when that is absolute
  and still exists, else the tab's starting directory, else home.
- It goes back to its former index, clamped to the tab count, and is selected.

Rationale: ADR-05 reopens a pane in the same place from its description, and a tab is the same idea one level down. The
closed tab's own directory is what an accidental close loses, so a new tab's rule of copying the selected tab's
directory would drop it. UTERM-001's residual risk carries over unchanged: a remote directory that also exists locally
is accepted.

### How ADR-04 changes

Original question: ADR-04 says "Every binding is uniterm's own". Its purpose was to keep libghostty's built-in bindings
out. This proposal keeps that purpose, but moves applet bindings to the applet. Decide how ADR-04 changes.

Decision: ADR-04 is rewritten in place. It has not reached main, so it is not yet formal, and no superseding ADR is
needed.

- Its binding bullet says no key comes from libghostty or from Ghostty's config.
- It adds the window-versus-applet rule. Window keys reach uniterm in every applet, and no applet, view inside one, or
  content it hosts can take them. An applet binds keys only for its own actions, and only keys uniterm does not
  reserve.
- Its config parts are unchanged. The reserved table, the canonical key form, the conflict handling, and the key-path
  routing stay in this proposal, since they are mechanism.
- The edit is made when this proposal is accepted.

Rationale: ADR-04's subject is already who owns key bindings, so the new rule belongs there. A later applet author who
reads only ADR-04 would otherwise put applet keys back in the host menu, or let hosted content take Cmd-W.

## Design Decisions (Open)

None.

## Risks

- **An applet's key shadows a window shortcut** — likelihood: medium, impact: medium.
  Mitigation: the window routes reserved keys to the menu before any view sees them, and the conflict rule drops an
  applet's claim with a warning. A unit test catches built-in conflicts.
- **Users with Cmd-Z habits lose pane undo** — likelihood: low, impact: low.
  Mitigation: Cmd-Shift-T is the common reopen key in browsers and editors.
- **UTERM-013 and the accepted UTERM-002 disagree until UTERM-002 is amended** — likelihood: high, impact: medium.
  UTERM-002 lives on its own branch. Its text says every uniterm binding runs a registry command and that menus do not
  read the registry. This proposal narrows the first and fills the second. A milestone built from UTERM-002's text
  alone would move Copy and Paste onto the registry. Mitigation: Impacts names both changes, and an M1 check holds
  the edit actions on the responder chain whichever milestone lands first. UTERM-002's text gets the matching
  amendment before its registry milestone starts.
- **Renaming File > Close Pane to Close drops users' App Shortcuts remaps of it** — likelihood: low, impact: low.
  Accepted: remaps match by title, so a one-time rename to a title that never changes again costs less than a title
  that switches with the tab count. Every other moved item keeps its title.
- **A user's remap can put a window action on a key an applet uses** — likelihood: low, impact: low.
  Accepted: a user's remap always wins, as UTERM-002 requires. The menus show the remap, so the effect is visible.
- **The applet contract grows before UTERM-005 to UTERM-010 are designed** — likelihood: medium, impact: low.
  The contract gains registry commands with menu homes, a three-way tab close answer, an undo-only description part,
  and closed-tab stamps with a reopen result. Later applet proposals may want a different shape. Mitigation: the
  contract is internal to one app bundle, so a change is a refactor, not a migration. The layout file's format does
  not change, and command IDs and stamps are never persisted. No one-way door is involved.

## Milestones

### M1: Applet-declared shortcuts

**Status:** NOT STARTED

Builds on UTERM-002's command registry milestone.

- An applet declares its shortcuts as registry commands, and they work only while that applet has focus
- A reserved window shortcut works in every applet, and an applet cannot claim it
- The terminal's tab, text size, and clear shortcuts come from the terminal, not uniterm
- Cut, Copy, Paste, and Select All work in the terminal, the launcher's fields, and the Settings rows
- The standard edit actions are responder-chain items, not registry commands, whichever of this milestone and
  UTERM-002's registry milestone lands first
- With two windows focused on different applet types, the menus show the key window's applet items. With Settings or a
  sheet key, applet items are disabled
- A command's action does not keep its applet alive after close
- Cmd-W closes the selected tab while the applet has two or more, and the pane at the last tab
- File > Close keeps its title whatever the tab count, and the palette's close command runs the same action
- Declining the close dialog for a running tab keeps the tab and the pane, even when the tab count drops to one while
  the dialog is open
- A second Cmd-W while a tab close dialog is open does nothing
- A reserved key reaches uniterm's menu even when the focused applet view would handle it
- A reserved key whose menu item is disabled, such as Cmd-Shift-T with nothing to reopen, is consumed and never reaches
  the view
- The Edit menu has Redo on Cmd-Shift-Z beside Cut, Copy, Paste, Select All, and Undo
- Text size items sit in View, New Tab in File, and Clear in the terminal's applet menu. An applet with no such items
  shows no applet menu
- Moved items keep their current titles, such as Clear Screen, so existing App Shortcuts remaps still match. File >
  Close is the one deliberate rename, from Close Pane
- The conflict warning says what to do next
- An applet command on a reserved key, or two commands of one applet on one key, keeps working without the key, and one
  warning per applet type names the applet, the command, and the key
- Cmd-} and Cmd-Shift-] count as the same key in the conflict check
- A unit test fails when any built-in applet command claims a reserved key or a key another of its commands holds
- The launcher keeps Cmd-1 to Cmd-9
- After an App Shortcuts remap of a uniterm item, the new key is reserved and the old default is not
- When a remap puts two items on one key, the remapped item runs, with a terminal or an applet view focused
- A remap that changes the reserved set rechecks applet keys, and a key it drops gets the one warning
- A remap made in System Settings while uniterm runs takes effect without a relaunch, or at a stated point. Two remaps
  onto one key resolve by one defined rule

### M2: Reopen with Cmd-Shift-T

**Status:** NOT STARTED

- Closing a terminal tab keeps its description in the terminal's closed-tab list
- Cmd-Shift-T reopens the newest close in the window, tab or pane. A tab reopens in its pane, in the same working
  directory rule as a pane, at its former index clamped to the tab count. It is selected and its pane takes focus
- The index recorded for a closed tab is its index after the close dialog returns
- A reopen whose session fails to start, or a pane that does not fit, keeps its entry and place. The same press
  reopens the next-older close, and one status message names both
- With pane B too large to fit and tab T closed before it, Cmd-Shift-T reopens T and B stays for a larger window
- With closed tabs at stamps 3 and 6 in one pane and a pane close at stamp 4, a failed reopen of the tab at 6 reopens
  the pane at 4
- Reopening an older pane past a failed newer one removes only the older entry
- A failed tab reopen leaves no half-built tab, and the selected tab, focus, and the entry's stamp and index are
  unchanged
- When every close in the window fails, the one status message says nothing reopened
- A pane's fit is checked before its applet is built
- Closing a tab in pane A, then closing pane B, then pressing Cmd-Shift-T reopens B, even though A has focus
- Closing tab B, then its pane, then pressing Cmd-Shift-T twice brings back the pane and then B
- Close stamps come from a per-window counter the host issues, never the wall clock
- A closed tab's stamp is taken after the close dialog returns, like its index
- A reopened pane's closed tabs keep their old stamps and sort correctly against closes made since
- The closed-tab list drops its oldest entry at the policy depth
- The closed-tab list is not in the layout file, and a change to the closed-tab list alone is not a layout change
- A tab whose shell exited on its own adds no closed-tab entry, as a pane whose applet exited adds no undo entry
- The UI tests that pressed Cmd-Z to reopen a pane press Cmd-Shift-T instead, and a Cmd-Z test shows panes are untouched
- Cmd-Z undoes a text edit in a focused text field, and does nothing to panes

## Decision Log

- 2026-11-01: Drafted from the user's walkthrough of the built app, feedback F1 to F3. The three settled decisions
  are the user's.
- 2026-11-01: Review start: 2 milestones, 3 settled decisions, 2 risks, no `**Live after:**` lines or row gates, no
  out-of-scope statements; the user asked for a converge-then-ask review of every open question. Proposal at commit
  "Propose window versus applet shortcuts and Cmd-Shift-T reopen".
- 2026-11-01: Cmd-Shift-T with no closed tab in the focused pane reopens the last closed pane. The third settled
  decision already said so, so the open question was closed without a vote.
- 2026-11-01: Each applet item names its menu home. Standard edit actions stay fixed uniterm Edit items on the
  responder chain, and the Edit menu gains Cut.
- 2026-11-01: Amended the first settled decision, which listed copy, paste, and select all among the terminal's
  declared shortcuts. The terminal still implements them, but uniterm keeps the Edit items, since text fields outside
  the terminal paste only through them. The user chose this narrowing.
- 2026-11-01: A shortcut declaration is a command with a stable, namespaced, never-reused ID, a title, an optional
  key, an enabled query, and an async-capable action. Standard edit actions are not commands. (addition) Settles part
  of UTERM-002's open "Command source" question.
- 2026-11-01: uniterm owns Cmd-W and asks the focused applet to close its tab. The applet answers closed, declined, or
  nothing to close, and only the last closes the pane.
- 2026-11-01: An applet's closed-tab list rides in an undo-only part of its description, never written to the layout
  file, at a fixed policy depth. (addition) It adds an undo-only field to the applet contract.
- 2026-11-01: The reserved set is uniterm's window command keys, the fixed Edit keys, and AppKit's own menu keys. The
  window routes reserved keys to the menu before any view sees them.
- 2026-11-01: A key conflict drops the key and keeps the command, warns once per applet type, and a unit test catches
  built-in conflicts. Two commands of one applet on one key both lose it.
- 2026-11-01: A reopened tab follows the pane's working-directory rule and returns to its former index, selected.
- 2026-11-01: ADR-04 is rewritten in place to carry the window-versus-applet key rule, when this proposal is
  accepted. ADR-04 has not reached main, and the user ruled that an ADR off main is not yet formal.
- 2026-11-01: Coherence review, full pass. UTERM-013 was written against UTERM-002's draft. UTERM-002 is accepted on
  its own branch, with a shared command registry, synchronous run actions, Cmd-Shift-P as the palette key, and App
  Shortcuts remaps that must win. Four design findings went to the user. Routed the rest to M1 and M2: a disabled
  reserved key is consumed, the Edit menu gains Redo, menu placements and kept titles, the warning's next step, the
  closed-tab layout-change rule, exited tabs, and the Cmd-Z UI tests. Fixed the Summary, Motivation, and Impacts.
- 2026-11-01: Amended "What one shortcut declaration is". It said applets declare their own command type with an
  async-capable action, and that this settled part of UTERM-002's open "Command source". Applet commands are now
  entries in UTERM-002's registry, with its synchronous run action, and UTERM-002's registry milestone builds it. Added
  UTERM-002 to the Dependencies. (addition) Menus read the registry, which UTERM-002 left undone.
- 2026-11-01: Amended "Who decides what Cmd-W closes" and the menu placement decision. Placement listed Close Tab as an
  applet item in File, against uniterm owning Cmd-W. Cmd-W is now one uniterm item with the fixed title "Close", so
  App Shortcuts remaps keep matching it.
- 2026-11-01: Amended "Which keys uniterm reserves". The set came from a static table. It now reads uniterm's live
  menu keys after App Shortcuts remaps, guards default keys only, and lets a user's remap win, with uniterm choosing
  the remapped item itself. UTERM-002's accepted M1 check requires this.
- 2026-11-01: Amended the second and third settled decisions, the user's own, and the fall-through decision. They said
  Cmd-Shift-T reopens the focused pane's newest closed tab, else the last closed pane, and that uniterm asks only the
  focused applet. Closing a pane moves focus to a neighbor, so a neighbor's closed tab took Cmd-Shift-T ahead of the
  pane. Cmd-Shift-T now reopens the newest close in the window. Applets stamp closed tabs from a host counter, and
  uniterm queries each applet's newest stamp. The user chose this. (addition) It adds an applet query and a
  host-issued stamp.
- 2026-11-01: Re-check pass. Amended the third settled decision's failure bullet, which said a failed reopen keeps its
  entry and does not block older closes. Under a newest-stamp query, the failed entry was picked on every press. One
  Cmd-Shift-T now walks closes newest first and stops at the first that reopens. Failed entries keep their place, and
  an applet's tab reopen reports success. Converged in 1 pass on the critic's added option. The user chose this.
- 2026-11-01: Re-check pass. Stated that the standard edit actions stay off UTERM-002's registry, which narrows its
  "every uniterm binding runs a registry command". It had claimed to conform. Added the narrowing to Impacts and an M1
  check. Routed the stamp timing, per-window counter, remap recheck, and Close rename to M1 and M2. Rejected a check on
  hidden grace-tier panes, which UTERM-001 M10 removed.
- 2026-11-01: Final re-check pass. Amended the second settled decision, which said uniterm asks applets for the
  recency of their newest closed tab. The walk needs every stamp, so each applet now reports its closed-tab stamps
  newest first, and reopens a tab by stamp with a success result. The user's fall-through answer already named this.
  Routed four checks to M2. This fix was not re-checked, since the proposal loop's three passes were used.
- 2026-11-01: Risk review. Reworded the shadowing risk's mitigation for the key-path routing. Added four risks: the
  disagreement with UTERM-002 until it is amended (mitigated), the Close rename dropping remaps (accepted), a user remap
  onto an applet key (accepted), and the applet contract growing ahead of UTERM-005 to UTERM-010 (mitigated). None is
  high likelihood and high impact. No one-way door: the layout format is unchanged, and nothing new is persisted.
- 2026-11-01: The user kept both accepted risks, the Close rename and a user remap onto an applet key.
- 2026-11-01: ADR candidate (cuts across the system, departs from the past): window keys reach uniterm in every applet,
  nothing an applet hosts can take them, and applets bind only unreserved keys for their own actions. Written as an
  in-place rewrite of ADR-04, which has not reached main.
- 2026-11-01: ADR candidate (cuts across the system): closed panes and closed tabs live in memory only, and no undo
  state reaches the layout file. Declined: the user chose not to write it. UTERM-001 and this proposal record it.
- 2026-11-01: ADR candidate (cuts across the system): command IDs are namespaced by owner and never reused. Waits on
  UTERM-003, whose Janet API will be the first caller to store an ID.
- 2026-11-01: ADR candidate (cuts across the system): applets own their closed-tab lists, stamped from a host counter,
  and the window reopens the newest close across applets and panes. Waits on UTERM-005 to UTERM-010, which may reshape
  the applet contract.
- 2026-11-01: Accepted.
- 2026-11-01: Scheduled as UTERM-013 M1-M2 in queue.md.

## References

- UTERM-001: "Whether uniterm reads the user's Ghostty config" and "What undo close restores"
- ADR-04
- ADR-05

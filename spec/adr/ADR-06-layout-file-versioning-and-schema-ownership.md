# ADR-06: The Layout File Is Versioned in Two Layers, Each With One Owner

**Status:** accepted
**Date:** 2026-11-01

## Context

The layout file is stored data that every later build of uniterm reads. It holds structure that uniterm owns: windows,
the pane tree, and node IDs. It also holds each pane's applet description, whose contents only that applet
understands.

Builds of different ages read the same file. A user may run a newer build, then an older one, then the newer one again.
Each applet's description also changes on its own schedule.

## Decision

The file has two layers. Each layer has one owner and its own version.

- uniterm owns the envelope. The envelope is the top-level schema version, the windows, the pane tree, and the wrapper
  around each pane's description: its applet type, its version, and its payload.
- Each applet type owns its payload and the payload's version.

Envelope versioning:

- The envelope carries an integer schema version.
- A reader upgrades an older envelope one version at a time.
- An envelope upgrade never reads or changes an applet payload.
- Any envelope change that an older reader cannot read back and write unchanged bumps the schema version. A new node
  kind is such a change.
- A reader that finds a newer schema version keeps the file aside unchanged and starts a default layout.

Payload versioning:

- An applet upgrades its own older payload versions when it reads them.
- Any payload change that an older reader cannot read back and write unchanged bumps that applet's version. This
  includes adding a field that an older reader would drop.
- A description whose type is unknown, whose version is newer, or that cannot be read is kept as its exact bytes. It is
  written back unchanged.

So version skew is lossless per pane. A newer applet's state survives a round trip through an older build.

## Rationale

One owner per layer keeps each migration local. uniterm never has to understand an applet's payload, and an applet
never has to understand the tree.

Bumping on any change that cannot round-trip turns a silent loss into a kept description. An older reader that sees a
newer version keeps the bytes instead of dropping the fields it does not know.

## Consequences

- A description that this build cannot read is never cleaned up, migrated, or scrubbed. It stays as written until a
  build that understands it rewrites it.
- An envelope bump costs more than a payload bump. An older build keeps the whole newer file aside, and a later upgrade
  reads the older build's layout, not the kept-aside one.
- An applet must bump its version for an additive change, even one that a newer reader handles without it.
- The pane tree's node IDs and their high-water mark live in the envelope, per ADR-02.

## Alternatives Considered

- **One version for the whole file.** Every applet change bumps it, and an older build then loses every pane, not one.
- **Readers keep unknown payload fields.** Additive changes would need no bump. But every applet must carry unknown
  fields through its decode and write them back. Swift's `Codable` drops unknown keys by default, so a single careless
  applet loses data.
- **uniterm migrates every payload.** That ties the host to every applet's internals.

## References

- UTERM-001: "What layout persistence restores, and in what format"
- ADR-02
- ADR-03

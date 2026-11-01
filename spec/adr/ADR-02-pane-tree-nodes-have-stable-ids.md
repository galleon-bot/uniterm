# ADR-02: Pane Tree Nodes Are Addressed by Stable ID

**Status:** accepted
**Date:** 2026-10-31

## Context

Each window's content area is a normalized N-ary pane tree. Normalization collapses a split left with one child. It
also merges a child into a parent with the same axis. Both rewrite the paths to nodes.

Many parts of uniterm need to name a node and find it again later:

- undo close, which reopens a pane beside a neighbor
- the layout file
- Janet scripts (UTERM-003)
- control and trust (UTERM-004)

## Decision

Every node in the pane tree has a stable ID.

- A node that survives a split, merge, or collapse keeps its ID.
- A removed node's ID is retired and never reused, including after a relaunch.
- A pane's ID never changes while the pane exists. A closed pane that is kept alive so undo can bring it back still
  exists. It keeps its ID and may return under it. Its ID is retired when the pane is discarded.

Nothing may address a node by its path in the tree, or by its index among its siblings.

## Rationale

Normalization keeps the tree matching what the user sees. The cost is that paths are not durable. A stable ID is the
only reference that survives normalization.

Retiring an ID instead of reusing it means a stale reference fails to resolve. It never silently resolves to a
different pane. That matters most where the reference crosses a trust boundary, as in UTERM-004.

## Consequences

- Every reference to a node must handle "this ID no longer exists". Undo, for example, needs a fallback placement.
- The layout file stores IDs, and a restored tree must never hand out an ID that was retired before quit.
- Adding a node kind, such as UTERM-004's group, leaves this rule unchanged.

## Alternatives Considered

- **Tree paths.** Paths are readable, but normalization rewrites them, so they break silently.
- **Both IDs and paths.** Paths would still mislead any caller that stored one.

## References

- UTERM-001: "Pane tree shape"
- UTERM-003: "API naming and shape"
- UTERM-004: "What anchors trust" and "Group node kind"
- ADR-05: a detached pane keeps its ID

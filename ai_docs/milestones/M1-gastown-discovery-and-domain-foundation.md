# M1 - Gastown Discovery & Domain Foundation

M1 establishes the domain adapters and read models that let Gmux reason about a Town in Gastown-native terms instead of raw filesystem paths.

## Included epics

- [EPIC-004 - Town discovery and rig inventory](../epics/EPIC-004-town-discovery-and-rig-inventory.md)
- [EPIC-005 - Agent and worktree resolution](../epics/EPIC-005-agent-and-worktree-resolution.md)
- [EPIC-006 - Read-only Beads and hooks ingestion](../epics/EPIC-006-read-only-beads-and-hooks-ingestion.md)

## Exit criteria

- Gmux can detect the active Town root and enumerate rigs with enough metadata to drive UI navigation.
- Gmux can resolve crew, polecat, refinery, and cross-rig worktree identities into stable open targets.
- Gmux can ingest Beads and hooks status as read-only data sources with normalized app models.

## Not in scope

- Operator cockpit polish or write actions that mutate Gastown state.
- Persistence or review tooling beyond what is required for read-model confidence.

## Research anchors

- [`deep-research-report.md`](../../deep-research-report.md)
- [`roadmap.md`](../roadmap.md)

# M0 - Fork Completion & Spec Infrastructure

M0 finishes the mechanical fork from cmux to Gmux and installs the repo-canonical planning system that later milestones depend on.

## Included epics

- [EPIC-001 - Gmux runtime identity completion](../epics/EPIC-001-gmux-runtime-identity-completion.md)
- [EPIC-002 - Gmux distribution and release identity](../epics/EPIC-002-gmux-distribution-and-release-identity.md)
- [EPIC-003 - Spec-driven delivery infrastructure](../epics/EPIC-003-spec-driven-delivery-infrastructure.md)

## Exit criteria

- Gmux can run beside cmux without sharing sockets, CLI helpers, caches, notifications, or remote state.
- Release artifacts, install flows, and published metadata present Gmux as a separate product.
- `ai_docs` is the canonical backlog and GitHub milestones/issues are synced from it.
- At least one full dry run and one live sync of the roadmap automation have completed without duplicates.

## Not in scope

- Gastown-specific operator features beyond the minimum read/write needs required to complete the fork.
- New end-user UI surfaces outside the fork-completion and planning work.

## Research anchors

- [`deep-research-report.md`](../../deep-research-report.md)
- [`roadmap.md`](../roadmap.md)

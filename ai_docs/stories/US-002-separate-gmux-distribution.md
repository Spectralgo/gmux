# US-002 - Separate Gmux Distribution

## Persona

User installing or upgrading Gmux as a standalone product.

## Narrative

As a user, I want Gmux to install and update as its own product so I can keep it alongside cmux without replacing cmux tooling or release metadata.

## Why it matters

A fork that still publishes cmux-branded DMGs, casks, or cleanup paths is operationally ambiguous and breaks coexistence.

## Acceptance criteria

- Release packaging, download names, casks, docs, and support-entry surfaces reference Gmux.
- CLI install flow produces `gmux` and does not overwrite `cmux`.
- Cleanup and zap logic target Gmux-owned state only.

## Linked epic and tasks

- Epic: `EPIC-002`
- Tasks: `TASK-003`, `TASK-029`, `TASK-004`

## Research anchors

- [`deep-research-report.md`](../../deep-research-report.md)
- [`M0`](../milestones/M0-fork-completion-and-spec-infrastructure.md)

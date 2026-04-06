# EPIC-010 - Hooks & Bead Write Actions

Milestone: [M3 - Automation, Hooks & Write Actions](../milestones/M3-automation-hooks-and-write-actions.md)

## Summary

Add safe, explicit write operations for hooks and Beads so operators can act from Gmux instead of treating it as a read-only dashboard.

## Stories

- [US-010 - Manage hooks and work state from Gmux](../stories/US-010-manage-hooks-and-work-state-from-gmux.md)

## Task refs

- `TASK-019`
- `TASK-020`

## Definition of done

- Hook edit and sync actions preserve Gastown’s merge and inheritance model.
- Bead and convoy mutations are traceable and scoped to supported actions.
- The write layer reuses the established read model and identity resolution primitives.

## Research anchors

- [`deep-research-report.md`](../../deep-research-report.md)
- [`roadmap.md`](../roadmap.md)

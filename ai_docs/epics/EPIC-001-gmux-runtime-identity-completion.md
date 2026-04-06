# EPIC-001 - Gmux Runtime Identity Completion

Milestone: [M0 - Fork Completion & Spec Infrastructure](../milestones/M0-fork-completion-and-spec-infrastructure.md)

## Summary

Complete the runtime isolation layer so Gmux can operate beside upstream cmux without sharing names, sockets, caches, notifications, helper paths, or remote relay state.

## Stories

- [US-001 - Side-by-side fork operation](../stories/US-001-side-by-side-fork-operation.md)

## Task refs

- `TASK-001`
- `TASK-002`

## Definition of done

- Local app and CLI flows no longer attach to cmux-owned runtime state.
- Developer helper scripts create and advertise `gmux`-scoped shims consistently.
- Coexistence bugs are tracked as fork-completion defects, not left as undocumented drift.

## Research anchors

- [`deep-research-report.md`](../../deep-research-report.md)
- [`roadmap.md`](../roadmap.md)

# EPIC-006 - Read-Only Beads & Hooks Ingestion

Milestone: [M1 - Gastown Discovery & Domain Foundation](../milestones/M1-gastown-discovery-and-domain-foundation.md)

## Summary

Ingest Beads and hooks state as read-only system-of-record data so Gmux can render accurate status without inventing its own shadow model.

## Stories

- [US-006 - Consume Beads and hooks read model](../stories/US-006-consume-beads-and-hooks-read-model.md)

## Task refs

- `TASK-011`
- `TASK-012`

## Definition of done

- Beads routes, ready work, and detail views can be driven from normalized adapter data.
- Hooks status is visible with enough structure to support future edit and sync actions.
- Read model ingestion failures surface clearly and preserve operator trust.

## Research anchors

- [`deep-research-report.md`](../../deep-research-report.md)
- [`roadmap.md`](../roadmap.md)

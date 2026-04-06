# US-006 - Consume Beads And Hooks Read Model

## Persona

Operator or toolsmith relying on Beads and hooks as the durable source of work state.

## Narrative

As a user, I want Gmux to consume Beads and hooks as source-of-truth data so the cockpit reflects the actual Gastown state instead of an app-local shadow model.

## Why it matters

The operator will not trust the product if its understanding of work, readiness, or hook status diverges from the canonical tools.

## Acceptance criteria

- Gmux can ingest read-only Beads routes, ready work, and detail data.
- Gmux can ingest hook targets and sync status from Gastown tooling.
- Data adapters expose normalized models that later write flows can reuse.

## Linked epic and tasks

- Epic: `EPIC-006`
- Tasks: `TASK-011`, `TASK-012`

## Research anchors

- [`deep-research-report.md`](../../deep-research-report.md)
- [`M1`](../milestones/M1-gastown-discovery-and-domain-foundation.md)

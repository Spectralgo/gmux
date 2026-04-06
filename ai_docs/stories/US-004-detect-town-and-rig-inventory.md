# US-004 - Detect Town And Rig Inventory

## Persona

Gastown user opening Gmux in a machine with one or more Town roots.

## Narrative

As a Gastown user, I want Gmux to detect my Town and rig inventory automatically so the app opens in domain terms instead of raw filesystem paths.

## Why it matters

Every later cockpit feature depends on knowing the Town root, rig boundaries, and role directory layout correctly.

## Acceptance criteria

- Gmux can locate the current Town root and validate prerequisites.
- Rig inventory exposes enough structure to navigate rigs, role directories, and health indicators.
- Missing prerequisites surface as actionable guidance instead of silent failures.

## Linked epic and tasks

- Epic: `EPIC-004`
- Tasks: `TASK-007`, `TASK-008`

## Research anchors

- [`deep-research-report.md`](../../deep-research-report.md)
- [`M1`](../milestones/M1-gastown-discovery-and-domain-foundation.md)

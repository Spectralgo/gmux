# EPIC-004 - Town Discovery & Rig Inventory

Milestone: [M1 - Gastown Discovery & Domain Foundation](../milestones/M1-gastown-discovery-and-domain-foundation.md)

## Summary

Detect the active Gastown Town and enumerate rigs, role directories, and prerequisite health so the rest of the product can reason about a valid domain root.

## Stories

- [US-004 - Detect Town and rig inventory](../stories/US-004-detect-town-and-rig-inventory.md)

## Task refs

- `TASK-007`
- `TASK-008`

## Definition of done

- Gmux can locate Town roots and explain missing prerequisites clearly.
- Rig inventory is normalized into app models rather than read ad hoc from views.
- Inventory failures are actionable and do not silently degrade downstream navigation.

## Research anchors

- [`deep-research-report.md`](../../deep-research-report.md)
- [`roadmap.md`](../roadmap.md)

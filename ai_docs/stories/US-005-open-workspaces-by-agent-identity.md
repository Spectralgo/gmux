# US-005 - Open Workspaces By Agent Identity

## Persona

Crew developer or operator jumping to a specific Gastown worker.

## Narrative

As a user, I want to open workspaces by agent identity so I can jump to the right crew, polecat, or cross-rig worktree without hunting through directories.

## Why it matters

Gastown’s directory model is role-specific; Gmux needs to preserve that model while giving users fast navigation.

## Acceptance criteria

- Gmux resolves crew, polecat, refinery, and cross-rig worktree identities into correct open targets.
- Identity-based routing works from the UI and from future automation surfaces.
- Resolution failures explain which part of the mapping is missing or invalid.

## Linked epic and tasks

- Epic: `EPIC-005`
- Tasks: `TASK-009`, `TASK-010`

## Research anchors

- [`deep-research-report.md`](../../deep-research-report.md)
- [`M1`](../milestones/M1-gastown-discovery-and-domain-foundation.md)

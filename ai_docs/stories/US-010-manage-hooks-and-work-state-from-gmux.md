# US-010 - Manage Hooks And Work State From Gmux

## Persona

Operator or toolsmith applying supported write actions from the cockpit.

## Narrative

As a user, I want to manage hooks and supported Bead or convoy state changes from Gmux so I can act on work without dropping back to a separate shell flow.

## Why it matters

Once the cockpit is trusted as a read model, the next step is to let users take the highest-value actions directly.

## Acceptance criteria

- Hooks edit and sync flows preserve Gastown’s inheritance and merge semantics.
- Supported Bead and convoy mutations are available with clear boundaries.
- UI writes reflect back into the read model quickly and traceably.

## Linked epic and tasks

- Epic: `EPIC-010`
- Tasks: `TASK-019`, `TASK-020`

## Research anchors

- [`deep-research-report.md`](../../deep-research-report.md)
- [`M3`](../milestones/M3-automation-hooks-and-write-actions.md)

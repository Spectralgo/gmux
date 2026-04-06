# US-001 - Side-By-Side Fork Operation

## Persona

Gmux operator who still has upstream cmux installed and active.

## Narrative

As a Gmux user, I want Gmux to run beside cmux without collisions so I can evaluate and adopt the fork incrementally.

## Why it matters

The fork is not credible if app launches, sockets, helper shims, remote state, or notifications still bind to cmux internals.

## Acceptance criteria

- Gmux app, CLI, sockets, app-support paths, remote relay state, and notifications are `gmux`-scoped.
- Running Gmux beside cmux does not clobber cmux developer shims or runtime state.
- Remaining coexistence gaps are explicitly tracked as M0 work items.

## Linked epic and tasks

- Epic: `EPIC-001`
- Tasks: `TASK-001`, `TASK-002`

## Research anchors

- [`deep-research-report.md`](../../deep-research-report.md)
- [`M0`](../milestones/M0-fork-completion-and-spec-infrastructure.md)

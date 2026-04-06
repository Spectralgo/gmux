# US-009 - Contextual Jump From Alert To Workspace

## Persona

Operator responding to notifications, inbox items, or other attention signals.

## Narrative

As a user, I want alerts to jump me into the correct workspace context so I do not have to reconstruct which rig, bead, or worker needs attention.

## Why it matters

Attention routing is one of the main workflow costs the product is supposed to remove.

## Acceptance criteria

- Alerts map to convoy, bead, and identity-aware workspace targets.
- Jump flows can restore the expected pane or view preset for the selected context.
- Non-focus commands keep the current focus unless the action is explicitly focusful.

## Linked epic and tasks

- Epic: `EPIC-009`
- Tasks: `TASK-017`, `TASK-018`

## Research anchors

- [`deep-research-report.md`](../../deep-research-report.md)
- [`M2`](../milestones/M2-operator-cockpit-mvp.md)

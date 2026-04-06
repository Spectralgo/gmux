# US-011 - Drive Gmux From CLI, Socket, And Inbox

## Persona

Automation engineer or operator scripting Gmux behavior.

## Narrative

As a user, I want CLI, socket, and inbox surfaces for Gmux so both humans and agents can drive the cockpit deterministically.

## Why it matters

cmux’s automation surfaces are part of the fork’s value proposition; Gmux needs equivalent control over its Gastown-native features.

## Acceptance criteria

- Core read and write flows can be reached through stable CLI or socket commands.
- Machine-readable outputs exist where automation depends on them.
- Mail or inbox items preserve enough context to reopen the relevant work state.

## Linked epic and tasks

- Epic: `EPIC-011`
- Tasks: `TASK-021`, `TASK-022`

## Research anchors

- [`deep-research-report.md`](../../deep-research-report.md)
- [`M3`](../milestones/M3-automation-hooks-and-write-actions.md)

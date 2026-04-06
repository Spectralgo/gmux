# US-012 - Recover Layout And Semantic Work Context

## Persona

User restarting or recovering Gmux after quit, crash, or machine interruption.

## Narrative

As a user, I want Gmux to restore my layout and semantic work context so recovery is fast even when live processes cannot be resumed perfectly.

## Why it matters

Restart pain is one of the main gaps called out in cmux’s current model; Gmux needs a layered recovery strategy.

## Acceptance criteria

- Last-session or named-session restore is explicit and reliable.
- Restart recovery can surface semantic clues such as Gastown checkpoints.
- Persistence UX documents which guarantees are metadata-only versus live-session backed.

## Linked epic and tasks

- Epic: `EPIC-012`
- Tasks: `TASK-023`, `TASK-024`

## Research anchors

- [`deep-research-report.md`](../../deep-research-report.md)
- [`M4`](../milestones/M4-persistence-review-and-advanced-integrations.md)

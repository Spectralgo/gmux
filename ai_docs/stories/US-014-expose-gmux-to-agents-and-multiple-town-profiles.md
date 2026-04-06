# US-014 - Expose Gmux To Agents And Multiple Town Profiles

## Persona

Advanced operator or platform engineer managing multiple Town contexts and agent integrations.

## Narrative

As a user, I want MCP-facing tools and multiple isolated Town profiles so I can integrate agents safely without mixing contexts.

## Why it matters

Once Gmux is a serious operator shell, it needs a clean platform boundary for agents and a clean isolation boundary for multiple Towns.

## Acceptance criteria

- Gmux defines a stable MCP-facing tool surface over its existing primitives.
- Multiple profiles isolate sockets, caches, actors, and Town roots.
- Agent integrations do not depend on brittle UI scraping.

## Linked epic and tasks

- Epic: `EPIC-014`
- Tasks: `TASK-027`, `TASK-028`

## Research anchors

- [`deep-research-report.md`](../../deep-research-report.md)
- [`M4`](../milestones/M4-persistence-review-and-advanced-integrations.md)

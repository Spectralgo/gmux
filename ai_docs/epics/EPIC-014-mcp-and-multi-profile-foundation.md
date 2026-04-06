# EPIC-014 - MCP & Multi-Profile Foundation

Milestone: [M4 - Persistence, Review & Advanced Integrations](../milestones/M4-persistence-review-and-advanced-integrations.md)

## Summary

Lay the platform groundwork for agent-facing MCP tooling and for multiple isolated Town profiles on the same machine.

## Stories

- [US-014 - Expose Gmux to agents and multiple Town profiles](../stories/US-014-expose-gmux-to-agents-and-multiple-town-profiles.md)

## Task refs

- `TASK-027`
- `TASK-028`

## Definition of done

- The repo defines the core MCP surface area and boundaries without overcommitting on transport details.
- Profile isolation keeps sockets, caches, actors, and Town roots from bleeding together.
- Later agent integrations can build on stable CLI/socket/domain primitives rather than UI scraping.

## Research anchors

- [`deep-research-report.md`](../../deep-research-report.md)
- [`roadmap.md`](../roadmap.md)

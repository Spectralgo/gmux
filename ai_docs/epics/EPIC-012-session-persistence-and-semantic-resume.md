# EPIC-012 - Session Persistence & Semantic Resume

Milestone: [M4 - Persistence, Review & Advanced Integrations](../milestones/M4-persistence-review-and-advanced-integrations.md)

## Summary

Restore layout and work context predictably after app restarts, while making the limits of true live-process preservation explicit.

## Stories

- [US-012 - Recover layout and semantic work context](../stories/US-012-recover-layout-and-semantic-work-context.md)

## Task refs

- `TASK-023`
- `TASK-024`

## Definition of done

- Users can save and restore named sessions or last-session metadata reliably.
- Crash or restart recovery can surface Gastown checkpoint data as a semantic resume aid.
- Persistence options document their tradeoffs instead of implying impossible guarantees.

## Research anchors

- [`deep-research-report.md`](../../deep-research-report.md)
- [`roadmap.md`](../roadmap.md)

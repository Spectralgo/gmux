# US-003 - Repo-Canonical AI-Executable Roadmap

## Persona

Maintainer or AI coding agent picking up roadmap work from GitHub.

## Narrative

As a maintainer, I want the roadmap to live canonically in the repo and sync to GitHub so agents can execute tasks without hidden context.

## Why it matters

Planning drift between docs and GitHub issues makes autonomous execution brittle and causes repeated clarification work.

## Acceptance criteria

- `ai_docs` contains milestone, epic, story, and task traceability with stable IDs.
- GitHub issues and milestones are generated from repo docs, not edited manually, and delivered items close from the canonical backlog state.
- Task issues are decision complete and point back to the canonical docs.

## Linked epic and tasks

- Epic: `EPIC-003`
- Tasks: `TASK-005`, `TASK-006`

## Research anchors

- [`deep-research-report.md`](../../deep-research-report.md)
- [`roadmap.md`](../roadmap.md)

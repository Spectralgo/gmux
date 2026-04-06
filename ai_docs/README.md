# Gmux AI Docs

`ai_docs` is the canonical planning and execution source for `Spectralgo/gmux`.

This folder exists so a human or AI coding agent can pick up a task with minimal extra context and know:

- what the product is trying to achieve
- how the work is sequenced
- which milestone/epic/story/task a change belongs to
- which GitHub issue is machine-managed from the repo

## Source Of Truth

The source order is:

1. `ai_docs/backlog.yaml`
2. milestone, epic, and story docs under `ai_docs/`
3. [`deep-research-report.md`](../deep-research-report.md) as the upstream product research document

GitHub milestones and roadmap issues are execution artifacts synced from these files. They are not the planning master.

For volatile external CLI behavior, especially Gastown and Beads command semantics, treat upstream docs as the authority and refresh assumptions before updating roadmap-managed tasks.

## ID Conventions

- Milestones: `M0` to `M4`
- Epics: `EPIC-001`, `EPIC-002`, ...
- User stories: `US-001`, `US-002`, ...
- Tasks: `TASK-001`, `TASK-002`, ...

Every task must link to at least one story. Every story must link to an epic and one or more tasks.

## backlog.yaml Format

`ai_docs/backlog.yaml` is stored as JSON-compatible YAML on purpose. That gives us:

- deterministic formatting in git
- zero parser dependencies for the sync tool
- easy machine updates for GitHub issue numbers and URLs

Do not hand-edit GitHub issue numbers in issue bodies. Update `backlog.yaml` or rerun the sync tool instead.

Backlog lifecycle rules:

- `delivery_state` on milestones, epics, and tasks is canonical and must be `open` or `done`.
- Open tasks also carry a readiness `state:*` label.
- Done tasks remain in the backlog for traceability, but the sync tool closes them on GitHub and removes readiness labels.

## Managed GitHub Objects

The sync tool manages:

- roadmap labels
- roadmap milestones
- epic issues
- task issues

Managed issues include a machine marker:

```md
<!-- Managed-by: ai_docs -->
```

The sync tool overwrites managed issue metadata and body content except for the `## Freeform notes` section, which is preserved.

## Workflow

1. Update `ai_docs/backlog.yaml` and the related milestone/epic/story docs.
2. Run a dry run:

```bash
npm run ai-docs:dry-run
```

3. Optionally run the script self-check:

```bash
npm run ai-docs:self-check
```

4. Apply the sync:

```bash
npm run ai-docs:sync
```

5. Commit the updated docs, script changes, and any refreshed GitHub IDs in `backlog.yaml`.

If the sync will generate GitHub issue links back into this repo, push the referenced docs before or immediately after the sync so the links resolve on GitHub.

## Files

- `roadmap.md`: top-level program view
- `agent-contract.md`: implementation rules every task can assume
- `milestones/`: delivery-wave goals and exit criteria
- `epics/`: execution slices within milestones
- `stories/`: stable behavior contracts tied to tasks

## Guardrails

- Keep task issues decision complete.
- Keep stories product-facing and implementation-light.
- Keep epics grouped by outcome, not by file ownership.
- Keep milestones as delivery waves, not generic release buckets.

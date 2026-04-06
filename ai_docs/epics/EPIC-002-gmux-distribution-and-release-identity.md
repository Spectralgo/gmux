# EPIC-002 - Gmux Distribution & Release Identity

Milestone: [M0 - Fork Completion & Spec Infrastructure](../milestones/M0-fork-completion-and-spec-infrastructure.md)

## Summary

Rebrand the release, installation, and packaging surfaces so Gmux ships as a distinct product, not a cosmetically renamed cmux build.

## Stories

- [US-002 - Separate Gmux distribution](../stories/US-002-separate-gmux-distribution.md)

## Task refs

- `TASK-003`
- `TASK-004`

## Definition of done

- Release assets, Homebrew metadata, and install flows all use Gmux names and identifiers.
- The shipped CLI installs as `gmux` and coexists with `cmux`.
- Packaging automation stops mutating cmux-only metadata or cleanup paths.

## Research anchors

- [`deep-research-report.md`](../../deep-research-report.md)
- [`roadmap.md`](../roadmap.md)

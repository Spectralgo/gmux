# Gmux Roadmap

This roadmap distills [`deep-research-report.md`](../deep-research-report.md) into a delivery program for `Spectralgo/gmux`.

## Product Direction

Gmux has two parallel obligations:

1. finish the fork so it behaves and ships as a true alternative to cmux
2. evolve into a Gastown-native operator cockpit built on convoys, beads, hooks, identity, and recoverable work state

The roadmap is therefore sequenced as delivery waves, not generic releases.

## Delivery Waves

| Milestone | Purpose | Primary Output |
| --- | --- | --- |
| `M0` | Finish the fork and install the planning system | a clean Gmux identity plus repo-canonical spec sync |
| `M1` | Build the Gastown read model | Town, rig, identity, Beads, and hooks discovery |
| `M2` | Ship the operator cockpit MVP | convoy-first attention views and bead context surfaces |
| `M3` | Make the shell programmable and actionable | hooks/bead writes, CLI/socket expansion, mail workflow |
| `M4` | Add durable recovery and advanced integrations | sessions, semantic resume, review UX, MCP, profiles |

## Sequencing Rules

- `M0` must complete before public roadmap execution accelerates, because fork identity and release packaging affect every downstream task.
- `M1` establishes the domain adapters that every operator-facing view depends on.
- `M2` uses the `M1` read model to deliver the first usable Gastown-native cockpit.
- `M3` adds mutations and automation only after the read model and operator views are stable.
- `M4` adds persistence and advanced integrations after core workflows are trustworthy.

## Planning Principles

- `ai_docs` is canonical.
- GitHub issues are generated from the backlog.
- Tasks must be agent-ready and decision complete.
- Stories describe behavior; tasks describe implementation.
- Milestones group user-visible outcomes, not code ownership.

## Research Traceability

This roadmap intentionally mirrors the research report themes:

- fork completion and separate product identity
- convoy-first operator UX
- Beads as the system of record
- hooks as managed integration surfaces
- persistence as layered behavior, not a single feature
- MCP and multi-profile work as later-stage platform features

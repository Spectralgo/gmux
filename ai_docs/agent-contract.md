# Gmux Agent Contract

This file defines the execution contract for any roadmap-managed task in `Spectralgo/gmux`.

## Canonical Planning Inputs

Before implementing a roadmap task, read:

1. `ai_docs/backlog.yaml`
2. the linked story doc in `ai_docs/stories/`
3. the linked epic doc in `ai_docs/epics/`
4. this contract

Do not treat GitHub issues as the planning source of truth. Managed issue bodies mirror `ai_docs`.

## Build Rule

After code changes, build with a tagged debug app:

```bash
./scripts/reload.sh --tag <task-slug>
```

Do not use an untagged debug app. Tagged builds isolate bundle IDs, sockets, logs, and derived data.

## Test Rule

Do not run local tests unless the task explicitly says otherwise.

- Prefer CI or the VM for tests.
- If local verification is needed, use targeted non-test checks and the tagged debug build.
- Report any unrun tests explicitly in the final task summary.

## Runtime Identity Invariants

Gmux work must preserve the forked product identity:

- app name: `Gmux`
- CLI name: `gmux`
- bundle IDs: `com.gmuxterm...`
- socket, cache, and application-support paths: `gmux`, not `cmux`
- release assets and packaging must present Gmux as a separate product

If upstream cmux changes reintroduce `cmux`-scoped runtime or distribution identifiers, preserve the Gmux fork behavior while merging the functional change.

## Git Expectations

- Default branch naming for implementation work: `codex/<task-id>-<slug>`
- Commit subject convention: `<TASK-ID>: <short description>`
- Do not rewrite managed issue bodies by hand; change `ai_docs` and rerun sync
- Do not revert unrelated user changes in the worktree

## Launch And Install Caveats

- `/usr/local/bin` may not be writable in every environment; prefer the repo’s tagged CLI path or `/opt/homebrew/bin` when verifying locally
- `reload.sh` is the supported path for app builds and dev CLI shims
- release packaging must remain isolated from upstream cmux artifacts and casks

## Definition Of Done

A roadmap task is done when:

- the implementation matches the linked story and epic
- acceptance criteria are satisfied
- verification steps in the task issue are completed or explicitly called out as pending
- the tagged build still succeeds if app code or runtime scripts changed
- `ai_docs` and any managed issue metadata stay in sync

# Rig Panel — Design Review Against Official Docs

Reviewed against `GASTOWN-KNOWLEDGE-BRIEF.md` (official Gas Town docs) and the original `interaction-spec.md`.

---

## Correct (keep as-is)

- **Data source**: `AgentHealthAdapter` correctly uses `gt status --json` as the primary machine-readable endpoint, matching the knowledge brief's recommended data sources.
- **Bead counts**: `RigPanelAdapter.loadBeadCounts()` correctly uses `bd list --json --all -n 0` and filters by rig prefix, matching the brief's recommended approach.
- **Doctor integration**: Health section properly calls `gt doctor --json --rig <rigId>` and parses pass/warn/fail with expandable details. Matches the brief's watchdog/diagnostics recommendations.
- **Infrastructure agents grouped**: Refinery, Witness, and Deacon are correctly mapped to the `.infrastructure` role group in `AgentRoleGroup.from(role:)` (line 164–169 of `DesignTokens.swift`). They appear in a collapsible section.
- **Role grouping order**: The four groups (Coordination, Workers, Specialists, Infrastructure) follow a logical hierarchy matching the brief's town-level/rig-level distinction.
- **Convoy stranded detection**: Work section correctly shows a "stranded" badge on convoys with `.stranded` attention state, matching the brief's definition that stranded = ready work with no polecats assigned.
- **Cross-panel navigation**: Agent names link to Agent Profile, bead counts link to Convoy Board filtered by status, convoy names link to Convoy Board — all via NotificationCenter, matching the spec's navigation table.
- **Design tokens**: All colors, typography, spacing, and animations use `GasTownColors`, `GasTownTypography`, `GasTownSpacing`, `GasTownAnimation` tokens. No hardcoded values.
- **Localization**: All user-facing strings use `String(localized:defaultValue:)` with the `rigPanel.*` key convention.
- **Health traffic lights**: Build, CI, Dolt, Disk, Doctor use the `HealthSignal` enum (green/amber/red/unknown) with correct color mapping.
- **Refresh strategy**: Matches the established `TownDashboardPanel` pattern — initial load on appear, auto-refresh via 8s `refreshTick`, silent refresh skips loading state and only publishes on change. Health on slower 24s cadence.
- **Accessibility**: VoiceOver labels on status dots, context bars, health rows, bead counts, convoy progress, and infrastructure toggle all present.

---

## Gaps (needs update)

### GAP 1 — CRITICAL: Polecats shown as "idle" (violates docs)

**File**: `Sources/Panels/RigPanelSections/RigTeamSection.swift`, lines 209–219

The knowledge brief states in bold: *"If you show a polecat as 'idle' in your panel, your design is WRONG. A polecat that isn't working doesn't exist — it has been nuked."*

The current `agentStatusLabel()` returns `"idle"` for agents where `!isRunning && !hasWork`. This is applied uniformly to all roles including polecats.

**Fix**: The status logic must be role-aware. For polecats, the only valid states are:
| State | Condition | Color |
|-------|-----------|-------|
| Working | `isRunning && hasWork` | Green |
| Stalled | `!isRunning && hasWork` | Amber (not current red) |
| Zombie | Agent exists but session dead and work complete (needs nuke) | Red |

For non-polecat roles (mayor, crew, refinery, witness), "running" and "idle" remain valid.

The "stalled" → "stuck" rename is acceptable but the color should be amber (attention), not red (error). Stalled means needs intervention, not catastrophic failure. "Zombie" state is completely unrepresented — it needs a detection mechanism (e.g., session dead + work marked done but slot not released).

### GAP 2 — Config section missing official rig config fields

**File**: `Sources/Panels/RigPanelSections/RigConfigSection.swift` + `Sources/GasTown/RigConfig.swift`

The review directive lists these as official rig config fields: `status` (operational/parked/docked), `auto_restart`, `max_polecats`, `priority_adjustment`, `maintenance_window`, `dnd`.

`RigConfig.swift` only models: `type`, `version`, `name`, `git_url`, `default_branch`, `beads.prefix`.

`RigConfigSection.swift` only shows: Git URL, Default branch, Bead prefix.

Even the interaction spec wireframe listed Namepool and Merge strategy, which are also missing.

**Fix**:
1. Extend `RigConfig` to decode `status`, `auto_restart`, `max_polecats`, `priority_adjustment`, `maintenance_window`, `dnd`, `namepool`, `merge_strategy` from `config.json` (use optional properties with defaults for backward compatibility).
2. Show these in the Config section. `status` is particularly important — operational/parked/docked changes how the entire panel should feel.

### GAP 3 — Hook content not prominently surfaced

**File**: `Sources/Panels/RigPanelSections/RigTeamSection.swift`, line 161–165

The knowledge brief says: *"Your panels MUST surface what's on each agent's hook. This is the answer to 'What is this agent doing right now?'"*

The implementation shows `agent.currentTask` (the hooked bead ID, e.g., "hq-29z") in the agent row. This is present but minimal — just a bead ID with no context.

**Fix**: Show the bead title alongside the ID. The `gt status --json` output should include `hook_title` or similar. If not, a secondary lookup via `bd show <bead-id> --json` could populate it. Example: `hq-29z: Fix sidebar layout` instead of just `hq-29z`.

### GAP 4 — Missing "Spawn Polecat" and "Add Crew" action buttons

**File**: `Sources/Panels/RigPanelSections/RigPanelHeaderView.swift`, lines 57–75

The interaction spec defines four header action buttons: Open Workspace, Spawn Polecat, Add Crew, Run Doctor. The implementation only has Open Workspace and Run Doctor.

**Fix**: Add "Spawn Polecat" button (triggers `gt sling` via a spawn sheet) and "Add Crew" button (triggers crew creation sheet). These are core workforce management actions.

### GAP 5 — "Run Doctor" doesn't actually run doctor

**File**: `Sources/Panels/RigPanelSections/RigPanelHeaderView.swift`, line 69

The "Run Doctor" button calls `panel.refresh()`, which refreshes the entire panel including health (only on non-silent ticks). The interaction spec says it should "Execute `gt doctor --rig <name>` and refresh Health section."

**Fix**: Add a dedicated `panel.runDoctor()` method that specifically runs `gt doctor --fix --rig <rigId>` (the fix variant, since the user is explicitly requesting it), then refreshes the health section.

### GAP 6 — Missing merge queue info in Work section

**File**: `Sources/Panels/RigPanelSections/RigWorkSection.swift`

The interaction spec wireframe shows "Merge queue: 0 pending" in the Work section. The knowledge brief emphasizes the Refinery's merge pipeline as a core concept. Not shown.

**Fix**: Add merge queue count from `gt mq list --json` (or `gt mq list` filtered by rig). Show "Merge queue: N pending" below the convoys list. Link to the Refinery Panel via `.openRefineryPanel` notification.

### GAP 7 — No last commit info in header

**File**: `Sources/Panels/RigPanelSections/RigPanelHeaderView.swift`

The interaction spec wireframe shows "Last commit: c47faba (2h ago)" as a third line in the header. The implementation shows build status (passing/failing) but not the commit hash + relative time directly.

**Fix**: Extract the short hash and relative time from `healthIndicators.build` message (already parsed in `RigPanelAdapter.loadBuildStatus()`) and show it as a dedicated line in the header.

### GAP 8 — Sequential CLI loading (performance)

**File**: `Sources/GasTown/RigPanelAdapter.swift`, lines 64–108

The interaction spec recommends parallel CLI calls via `DispatchGroup`. The current `loadSnapshot()` runs agent loading, convoy loading, bead counts, and health indicators sequentially.

**Fix**: Wrap the four independent data loads (agents, convoys, beadCounts, health) in a `DispatchGroup` with concurrent `DispatchQueue.global().async` blocks, then `group.wait()` and combine. This should cut load time significantly since each CLI call takes 50–200ms.

### GAP 9 — Polecat three-layer architecture not surfaced

The knowledge brief explains that each polecat has three independent layers: Session (ephemeral), Sandbox (persistent), Slot (persistent). It specifically says: *"Your panel should show session count as a health metric (many sessions = resilient), not as a concern."*

None of this is visible in the current agent row. There's no session count, no sandbox state, no slot name distinction.

**Fix**: If `gt status --json` includes session count or layer data, surface it in the agent row (e.g., "12 sessions" as a small badge). This teaches users that session cycling is normal.

---

## Enhancement Opportunities

### ENH 1 — Convoy swarm visualization

The knowledge brief distinguishes convoys (persistent tracking units) from swarms (ephemeral polecat collections). The Work section shows convoy progress but doesn't show which/how many polecats form the swarm.

The spec wireframe shows "2 polecats assigned" per convoy — implementing this would teach the convoy/swarm distinction through the UI.

### ENH 2 — Rig status badge with operational semantics

If the `status` config field (operational/parked/docked) is surfaced, the header could show a prominent status badge. A "parked" rig would visually dim, a "docked" rig would show a maintenance indicator. This teaches users what rig states mean.

### ENH 3 — "View in Refinery" link

The interaction spec lists a "View in Refinery" cross-panel link. Adding this to the Work section (near merge queue info) would provide a direct path to the merge pipeline, reinforcing the Refinery's role in the merge flow.

### ENH 4 — Mail notification badges on agents

`AgentHealthEntry` already includes `unreadMail: Int`. The agent row doesn't show it. A small mail badge (e.g., red dot with count) on agents with unread mail would surface the "mail as nervous system" concept from the knowledge brief.

### ENH 5 — Boot/Deacon heartbeat freshness

The knowledge brief details the three-tier watchdog chain (Daemon → Boot → Deacon) with specific heartbeat thresholds (< 5 min = fresh, 5–15 min = nudge, > 15 min = wake). The infrastructure section could show heartbeat freshness on the Deacon row, making the watchdog chain visible.

### ENH 6 — Keyboard navigation within sections

The interaction spec defines Tab/Shift-Tab between sections, Arrow Up/Down within sections, Return/Space to activate, Escape to collapse. This accessibility layer is not yet implemented (`.focusable()` + keyboard handlers).

---

## Priority Fixes

1. **Polecat states (GAP 1)** — Showing "idle" for polecats directly contradicts the official docs and teaches users a concept that doesn't exist. This is the highest-impact correctness fix. Role-aware status logic is required.

2. **Config fields (GAP 2)** — The `status` field (operational/parked/docked) changes the semantic meaning of the entire panel. Without it, the panel can't communicate whether a rig is active, paused, or under maintenance. The other fields (`max_polecats`, `auto_restart`, `dnd`) are operational levers users need to see.

3. **Hook content (GAP 3)** + **Unread mail badges (ENH 4)** — The hook is "THE answer to what this agent is doing." Showing just a bead ID is insufficient; adding the bead title and surfacing unread mail counts would make the Team section a true command center rather than just a status list.

4. **Missing action buttons (GAP 4)** — "Spawn Polecat" and "Add Crew" are workforce management actions. Without them, the Rig Panel is read-only for workforce ops, forcing users back to the terminal.

5. **Parallel CLI loading (GAP 8)** — Each `loadSnapshot()` runs 4+ CLI calls sequentially. With 8-second auto-refresh, sequential loads risk overlapping refreshes or stale data. Parallelizing is straightforward and cuts wall-clock load time by ~3x.

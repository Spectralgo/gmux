import Foundation

/// Classification of a Gas Town workspace's git topology.
///
/// Gas Town workspaces come in four shapes:
///
/// | Kind | Location | Git shape |
/// |------|----------|-----------|
/// | `crewClone` | `<rig>/crew/<name>/` | Full clone (`.git` directory) |
/// | `polecatWorktree` | `<rig>/polecats/<name>/rig/` | Worktree (`.git` file) |
/// | `refineryWorktree` | `<rig>/refinery/rig/` | Worktree (`.git` file) |
/// | `crossRigWorktree` | `<rig>/crew/<combined-name>/` | Worktree (`.git` file) |
///
/// Classification uses git metadata (`.git` file vs. directory), not path
/// heuristics alone, because cross-rig worktrees live under `crew/` but are
/// still git worktrees rather than full clones.
enum WorktreeKind: String, Equatable, Hashable, CaseIterable {
    /// A persistent, user-managed full clone under `crew/<name>/`.
    case crewClone = "crew_clone"

    /// A witness-managed git worktree under `polecats/<name>/rig/`.
    case polecatWorktree = "polecat_worktree"

    /// The singular refinery git worktree at `refinery/rig/`.
    case refineryWorktree = "refinery_worktree"

    /// A cross-rig git worktree placed under the target rig's `crew/`
    /// directory, created by `gt worktree`. Preserves the originating
    /// agent's identity (BD_ACTOR and GT_ROLE).
    case crossRigWorktree = "crossrig_worktree"
}

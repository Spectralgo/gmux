import Foundation

/// The classified type of a workspace within a rig.
///
/// Each kind corresponds to a specific combination of git topology
/// (`.git` file vs directory) and role context (crew, polecat, etc.).
enum WorktreeKind: String, Equatable, CaseIterable, Codable {
    /// A full clone under `crew/<name>/` (`.git` is a directory).
    case crewClone

    /// A git worktree under `polecats/<name>/rig/` (`.git` is a file).
    case polecatWorktree

    /// The singular refinery worktree at `refinery/rig/` (`.git` is a file).
    case refineryWorktree

    /// A cross-rig worktree under `crew/<combined-name>/` (`.git` is a file).
    ///
    /// Created by `gt worktree` to let an agent work in another rig
    /// while preserving identity.
    case crossRigWorktree

    /// Whether this workspace is a git worktree (`.git` is a file)
    /// rather than a full clone.
    var isWorktree: Bool {
        switch self {
        case .crewClone: return false
        case .polecatWorktree, .refineryWorktree, .crossRigWorktree: return true
        }
    }
}

import Foundation

/// The result of successfully resolving an agent identity to a worktree.
///
/// Contains everything needed to open, label, and contextualize the workspace.
struct ResolvedWorktree: Equatable {
    /// The identity that was resolved.
    let identity: AgentIdentity

    /// Absolute path to the worktree root (the directory containing `.git`).
    let path: URL

    /// The classified workspace type.
    let kind: WorktreeKind

    /// The rig this worktree belongs to.
    let rig: Rig

    /// The role directory containing this worktree.
    let roleDirectory: RoleDirectory
}

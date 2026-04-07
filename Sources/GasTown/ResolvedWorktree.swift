import Foundation

/// The result of resolving an agent identity to a concrete worktree.
///
/// Carries the filesystem path, git topology classification, and enough
/// metadata for downstream routing by bead, convoy, or notification flows.
struct ResolvedWorktree: Equatable {
    /// The agent identity that was resolved.
    let identity: AgentIdentity

    /// Absolute path to the worktree root (the directory containing `.git`).
    let path: URL

    /// Classification of this workspace's git topology.
    let kind: WorktreeKind

    /// The rig this worktree belongs to.
    let rig: Rig

    /// The role directory containing this worktree.
    let roleDirectory: RoleDirectory
}

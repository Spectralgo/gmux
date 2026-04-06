import Foundation

/// Classifies a filesystem path as a specific ``WorktreeKind`` by inspecting
/// git metadata and its position within a rig's directory structure.
///
/// Classification uses two signals:
/// 1. **Git topology**: a `.git` *file* indicates a git worktree; a `.git`
///    *directory* indicates a full clone.
/// 2. **Role context**: the role and position within the rig determine which
///    specific kind applies (e.g. a worktree under `crew/` is cross-rig,
///    while one under `polecats/` is a polecat worktree).
///
/// This type is stateless and thread-safe.
enum WorktreeClassifier {

    /// The git topology detected at a path.
    enum GitTopology: Equatable {
        /// `.git` is a regular directory -- this is a full clone.
        case clone

        /// `.git` is a file pointing to a shared gitdir -- this is a worktree.
        case worktree

        /// No `.git` entry found at the path.
        case absent
    }

    /// Errors from worktree classification.
    enum ClassificationError: Equatable, Error {
        /// The path has no `.git` entry (not a git repository or worktree).
        case noGitMetadata(URL)

        /// The path's git topology does not match its role context.
        case topologyMismatch(path: URL, role: RigRole, expected: GitTopology, actual: GitTopology)
    }

    // MARK: - Public

    /// Detect the git topology at the given path.
    ///
    /// - Parameter path: A directory that may contain a `.git` entry.
    /// - Returns: The detected topology.
    static func detectTopology(at path: URL) -> GitTopology {
        let gitPath = path.appendingPathComponent(".git")
        let fm = FileManager.default

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: gitPath.path, isDirectory: &isDirectory) else {
            return .absent
        }

        return isDirectory.boolValue ? .clone : .worktree
    }

    /// Classify a workspace path within a rig's role directory.
    ///
    /// The classification combines git metadata inspection with the role
    /// context to produce a deterministic ``WorktreeKind``.
    ///
    /// - Parameters:
    ///   - path: Absolute path to the workspace root.
    ///   - role: The role this workspace lives under.
    /// - Returns: The classified ``WorktreeKind``.
    /// - Throws: ``ClassificationError`` if the path cannot be classified.
    static func classify(path: URL, role: RigRole) throws -> WorktreeKind {
        let topology = detectTopology(at: path)

        guard topology != .absent else {
            throw ClassificationError.noGitMetadata(path)
        }

        switch role {
        case .polecats:
            guard topology == .worktree else {
                throw ClassificationError.topologyMismatch(
                    path: path, role: role, expected: .worktree, actual: topology
                )
            }
            return .polecatWorktree

        case .refinery:
            guard topology == .worktree else {
                throw ClassificationError.topologyMismatch(
                    path: path, role: role, expected: .worktree, actual: topology
                )
            }
            return .refineryWorktree

        case .crew:
            return topology == .worktree ? .crossRigWorktree : .crewClone

        case .mayor, .witness:
            return topology == .worktree ? .polecatWorktree : .crewClone
        }
    }
}

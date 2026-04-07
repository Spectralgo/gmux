import Foundation

/// Resolves ``AgentIdentity`` values into concrete ``ResolvedWorktree`` results
/// using a pre-built ``RigInventorySnapshot``.
///
/// The resolver never re-traverses the filesystem for rig structure — it reads
/// the snapshot produced by ``RigInventoryAdapter``. Git metadata inspection
/// (`.git` file vs. directory) is the only filesystem access performed, and only
/// on the specific worktree path being resolved.
///
/// This type is stateless and thread-safe. It is designed to be called from UI,
/// CLI, socket, and notification flows without coordination.
enum AgentIdentityResolver {

    /// Errors from identity resolution.
    enum ResolutionError: Equatable, Error {
        /// The requested rig does not exist in the inventory snapshot.
        case rigNotFound(String)

        /// The role directory is missing or has no members.
        case roleNotAvailable(rig: String, role: RigRole)

        /// A multi-member role was queried for a member that does not exist.
        case memberNotFound(rig: String, role: RigRole, member: String, available: [String])

        /// The resolved path does not contain git metadata.
        case noWorktreeAtPath(identity: AgentIdentity, path: URL)

        /// The worktree's git topology does not match expectations for the role.
        case classificationFailed(identity: AgentIdentity, detail: String)
    }

    // MARK: - Public

    /// Resolve an agent address string to a worktree.
    ///
    /// Convenience that parses the address and delegates to
    /// ``resolve(identity:in:)``.
    ///
    /// - Parameters:
    ///   - address: A slash-separated agent address (e.g. `"gmux/polecats/chrome"`).
    ///   - snapshot: The current rig inventory snapshot.
    /// - Returns: A ``ResolvedWorktree`` on success.
    /// - Throws: ``AgentIdentity.ParseError`` or ``ResolutionError``.
    static func resolve(
        address: String,
        in snapshot: RigInventorySnapshot
    ) throws -> ResolvedWorktree {
        let identity = try AgentIdentity.parse(address)
        return try resolve(identity: identity, in: snapshot)
    }

    /// Resolve a structured identity to a worktree.
    ///
    /// - Parameters:
    ///   - identity: The agent identity to resolve.
    ///   - snapshot: The current rig inventory snapshot.
    /// - Returns: A ``ResolvedWorktree`` with path, kind, and metadata.
    /// - Throws: ``ResolutionError`` with actionable detail.
    static func resolve(
        identity: AgentIdentity,
        in snapshot: RigInventorySnapshot
    ) throws -> ResolvedWorktree {
        // 1. Find the rig.
        guard let rig = snapshot.rigs.first(where: { $0.id == identity.rig }) else {
            throw ResolutionError.rigNotFound(identity.rig)
        }

        // 2. Find the role directory.
        guard let roleDir = rig.roles[identity.role],
              roleDir.status == .present else {
            throw ResolutionError.roleNotAvailable(rig: identity.rig, role: identity.role)
        }

        // 3. Compute the worktree path.
        let worktreePath: URL
        if identity.role.isSingular {
            // Singular roles: workspace at <role>/rig/
            worktreePath = roleDir.path.appendingPathComponent("rig")
        } else {
            // Multi-member roles: workspace at <role>/<name>/ for crew,
            // or <role>/<name>/rig/ for polecats.
            guard let memberName = identity.name else {
                throw ResolutionError.roleNotAvailable(rig: identity.rig, role: identity.role)
            }

            // Verify the member exists in the inventory.
            guard roleDir.members.contains(memberName) else {
                throw ResolutionError.memberNotFound(
                    rig: identity.rig,
                    role: identity.role,
                    member: memberName,
                    available: roleDir.members
                )
            }

            switch identity.role {
            case .polecats:
                // Polecat worktrees live at <rig>/polecats/<name>/rig/
                worktreePath = roleDir.path
                    .appendingPathComponent(memberName)
                    .appendingPathComponent("rig")
            case .crew:
                // Crew clones (and cross-rig worktrees) live at <rig>/crew/<name>/
                worktreePath = roleDir.path.appendingPathComponent(memberName)
            default:
                worktreePath = roleDir.path.appendingPathComponent(memberName)
            }
        }

        // 4. Classify the worktree by inspecting git metadata.
        let kind: WorktreeKind
        do {
            kind = try WorktreeClassifier.classify(path: worktreePath, role: identity.role)
        } catch let error as WorktreeClassifier.ClassificationError {
            switch error {
            case .noGitMetadata:
                throw ResolutionError.noWorktreeAtPath(identity: identity, path: worktreePath)
            case .topologyMismatch(_, _, let expected, let actual):
                throw ResolutionError.classificationFailed(
                    identity: identity,
                    detail: "Expected \(expected) but found \(actual) at \(worktreePath.path)"
                )
            }
        }

        return ResolvedWorktree(
            identity: identity,
            path: worktreePath,
            kind: kind,
            rig: rig,
            roleDirectory: roleDir
        )
    }

    /// Resolve all known agents in a rig inventory snapshot.
    ///
    /// Iterates every rig and every role member, attempting resolution for
    /// each. Failures are captured alongside successes so that one broken
    /// worktree does not prevent others from being listed.
    ///
    /// - Parameter snapshot: The current rig inventory snapshot.
    /// - Returns: All successfully resolved worktrees and any failures.
    static func resolveAll(
        in snapshot: RigInventorySnapshot
    ) -> (resolved: [ResolvedWorktree], failures: [ResolutionFailure]) {
        var resolved: [ResolvedWorktree] = []
        var failures: [ResolutionFailure] = []

        for rig in snapshot.rigs {
            for (role, roleDir) in rig.roles.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                guard roleDir.status == .present else { continue }

                if role.isSingular {
                    let identity = AgentIdentity(rig: rig.id, role: role, name: nil)
                    do {
                        let result = try resolve(identity: identity, in: snapshot)
                        resolved.append(result)
                    } catch {
                        failures.append(ResolutionFailure(identity: identity, reason: "\(error)"))
                    }
                } else {
                    for member in roleDir.members {
                        let identity = AgentIdentity(rig: rig.id, role: role, name: member)
                        do {
                            let result = try resolve(identity: identity, in: snapshot)
                            resolved.append(result)
                        } catch {
                            failures.append(ResolutionFailure(identity: identity, reason: "\(error)"))
                        }
                    }
                }
            }
        }

        return (resolved, failures)
    }
}

/// A single identity that could not be resolved, with a diagnostic reason.
struct ResolutionFailure: Equatable {
    /// The identity that failed resolution.
    let identity: AgentIdentity

    /// Human-readable description of why resolution failed.
    let reason: String
}

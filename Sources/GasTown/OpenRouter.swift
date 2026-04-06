import Foundation

/// Resolves Gas Town identities into ``OpenIntent`` values.
///
/// This is the routing layer that all consumers (UI, CLI, socket, notifications,
/// future MCP) use to navigate by identity. It composes with the TASK-009
/// ``AgentIdentityResolver`` for agent-to-worktree resolution and adds
/// bead and convoy routing on top.
///
/// **Design invariants:**
/// - Stateless and thread-safe (caseless enum with static methods).
/// - Never shells out to `gt`, `bd`, or any external process.
/// - Never accesses the filesystem (that is ``WorktreeClassifier``'s job,
///   called transitively via ``AgentIdentityResolver``).
/// - Callers pre-fetch bead/convoy data and pass it in as value types.
///
/// **Focus policy** is part of every produced intent. Downstream executors
/// honor it without needing to know the routing origin.
enum OpenRouter {

    // MARK: - Route by Agent

    /// Route by agent address.
    ///
    /// Resolves the address to a worktree via ``AgentIdentityResolver``
    /// and produces an intent to open that worktree.
    ///
    /// - Parameters:
    ///   - address: A slash-separated agent address (e.g. `"gmux/polecats/chrome"`).
    ///   - snapshot: The current rig inventory snapshot.
    ///   - focus: Focus behavior for the resulting intent.
    /// - Returns: An ``OpenIntent`` targeting the agent's worktree.
    /// - Throws: ``OpenRoutingError.identityResolutionFailed`` on resolution failure.
    static func routeByAgent(
        address: String,
        in snapshot: RigInventorySnapshot,
        focus: FocusPolicy = .focusful
    ) throws -> OpenIntent {
        let resolved: ResolvedWorktree
        do {
            resolved = try AgentIdentityResolver.resolve(address: address, in: snapshot)
        } catch {
            throw OpenRoutingError.identityResolutionFailed(detail: "\(error)")
        }

        return OpenIntent(
            target: .agent(resolved),
            focusPolicy: focus,
            label: resolved.identity.address,
            convoyContext: nil,
            beadContext: nil
        )
    }

    /// Route by a pre-parsed agent identity.
    ///
    /// - Parameters:
    ///   - identity: The agent identity to resolve.
    ///   - snapshot: The current rig inventory snapshot.
    ///   - focus: Focus behavior for the resulting intent.
    /// - Returns: An ``OpenIntent`` targeting the agent's worktree.
    /// - Throws: ``OpenRoutingError.identityResolutionFailed`` on resolution failure.
    static func routeByAgent(
        identity: AgentIdentity,
        in snapshot: RigInventorySnapshot,
        focus: FocusPolicy = .focusful
    ) throws -> OpenIntent {
        let resolved: ResolvedWorktree
        do {
            resolved = try AgentIdentityResolver.resolve(identity: identity, in: snapshot)
        } catch {
            throw OpenRoutingError.identityResolutionFailed(detail: "\(error)")
        }

        return OpenIntent(
            target: .agent(resolved),
            focusPolicy: focus,
            label: resolved.identity.address,
            convoyContext: nil,
            beadContext: nil
        )
    }

    // MARK: - Route by Bead

    /// Route by bead ID.
    ///
    /// Resolves the bead's assignee to an agent address, then resolves that
    /// agent to a worktree. The bead ID is carried as context in the intent
    /// so downstream features (e.g. bead inspector) can bind to it.
    ///
    /// - Parameters:
    ///   - beadID: The bead identifier (e.g. `"gm-3rs"`).
    ///   - assignee: Pre-fetched assignee data from `bd show`.
    ///   - snapshot: The current rig inventory snapshot.
    ///   - focus: Focus behavior for the resulting intent.
    /// - Returns: An ``OpenIntent`` targeting the bead's assignee worktree.
    /// - Throws: ``OpenRoutingError.beadUnassigned`` if no assignee, or
    ///   ``OpenRoutingError.identityResolutionFailed`` if the assignee cannot be resolved.
    static func routeByBead(
        beadID: String,
        assignee: BeadAssignee,
        in snapshot: RigInventorySnapshot,
        focus: FocusPolicy = .focusful
    ) throws -> OpenIntent {
        guard let agentAddress = assignee.agentAddress else {
            throw OpenRoutingError.beadUnassigned(beadID: beadID)
        }

        let resolved: ResolvedWorktree
        do {
            resolved = try AgentIdentityResolver.resolve(address: agentAddress, in: snapshot)
        } catch {
            throw OpenRoutingError.identityResolutionFailed(detail: "\(error)")
        }

        return OpenIntent(
            target: .bead(beadID: beadID, resolvedWorktree: resolved),
            focusPolicy: focus,
            label: "\(beadID) (\(resolved.identity.address))",
            convoyContext: nil,
            beadContext: beadID
        )
    }

    // MARK: - Route by Convoy

    /// Route by convoy ID.
    ///
    /// Finds the first actionable tracked bead (not closed, has assignee),
    /// resolves its assignee to a worktree, and produces an intent with
    /// convoy context. If no actionable bead exists, produces an intent
    /// with a `nil` worktree for a dashboard-only view.
    ///
    /// - Parameters:
    ///   - convoyID: The convoy identifier (e.g. `"hq-cv-abc12"`).
    ///   - trackedBeads: Pre-fetched tracked beads from `gt convoy show`.
    ///   - snapshot: The current rig inventory snapshot.
    ///   - focus: Focus behavior for the resulting intent.
    /// - Returns: An ``OpenIntent`` targeting the convoy's first actionable worktree,
    ///   or a dashboard-only intent if no actionable bead exists.
    /// - Throws: ``OpenRoutingError.identityResolutionFailed`` if the actionable
    ///   bead's assignee cannot be resolved.
    static func routeByConvoy(
        convoyID: String,
        trackedBeads: [ConvoyTrackedBead],
        in snapshot: RigInventorySnapshot,
        focus: FocusPolicy = .focusful
    ) throws -> OpenIntent {
        // Find the first actionable bead.
        guard let actionable = trackedBeads.first(where: { $0.isActionable }),
              let assignee = actionable.assignee,
              let agentAddress = assignee.agentAddress else {
            // No actionable bead -- produce a dashboard-only intent.
            return OpenIntent(
                target: .convoy(convoyID: convoyID, resolvedWorktree: nil),
                focusPolicy: focus,
                label: convoyID,
                convoyContext: convoyID,
                beadContext: nil
            )
        }

        let resolved: ResolvedWorktree
        do {
            resolved = try AgentIdentityResolver.resolve(address: agentAddress, in: snapshot)
        } catch {
            throw OpenRoutingError.identityResolutionFailed(detail: "\(error)")
        }

        return OpenIntent(
            target: .convoy(convoyID: convoyID, resolvedWorktree: resolved),
            focusPolicy: focus,
            label: "\(convoyID) -> \(resolved.identity.address)",
            convoyContext: convoyID,
            beadContext: actionable.beadID
        )
    }
}

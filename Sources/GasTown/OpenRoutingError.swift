import Foundation

/// Errors from the open-routing layer.
///
/// These errors describe failures in the ``OpenRouter`` routing primitives.
/// They are domain-level errors suitable for programmatic handling; user-facing
/// localization happens at the executor or UI layer.
enum OpenRoutingError: Error, Equatable {
    /// Agent identity resolution failed.
    ///
    /// Wraps errors from ``AgentIdentityResolver`` with a human-readable detail.
    case identityResolutionFailed(detail: String)

    /// The bead has no assignee and cannot be routed to a worktree.
    case beadUnassigned(beadID: String)

    /// The convoy has no actionable beads (all closed or unassigned).
    case convoyEmpty(convoyID: String)

    /// The convoy's first actionable bead has no assignee.
    case convoyBeadUnassigned(convoyID: String, beadID: String)
}

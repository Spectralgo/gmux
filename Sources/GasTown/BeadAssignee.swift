import Foundation

/// Pre-fetched bead assignment information for routing.
///
/// Callers fetch this from `bd show --json` (or equivalent) and pass it
/// to ``OpenRouter.routeByBead(beadID:assignee:in:focus:)``. The router
/// does not shell out or inspect bead state -- it only uses the pre-fetched
/// data to resolve the agent address to a worktree.
struct BeadAssignee: Equatable {
    /// The agent address assigned to this bead (e.g. `"gmux/polecats/chrome"`).
    ///
    /// `nil` when the bead is unassigned.
    let agentAddress: String?

    /// The rig this bead belongs to, resolved from `routes.jsonl` prefix mapping.
    let rig: String
}

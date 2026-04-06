import Foundation

/// Pre-fetched tracked bead information from a convoy.
///
/// Callers fetch this from `gt convoy show <id> --json` and pass the list
/// to ``OpenRouter.routeByConvoy(convoyID:trackedBeads:in:focus:)``.
struct ConvoyTrackedBead: Equatable {
    /// The bead ID tracked by the convoy.
    let beadID: String

    /// The bead's current status (e.g. `"open"`, `"closed"`, `"in_progress"`).
    let status: String

    /// The bead's assignee, if known.
    let assignee: BeadAssignee?

    /// Whether this bead is considered actionable for routing purposes.
    ///
    /// A bead is actionable if it is not closed and has an assignee.
    var isActionable: Bool {
        status != "closed" && assignee?.agentAddress != nil
    }
}

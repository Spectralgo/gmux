import Foundation

// MARK: - Notification Context
//
// Structured context that enriches a notification or event with enough
// routing information to jump back to the relevant convoy, bead, or
// workspace.
//
// Design: pure data, no process spawning, no file I/O.  Produced by
// event sources (socket commands, CLI, mail pipeline) and consumed by
// ``NotificationRouter`` to create jump targets.
//
// The separation between context (stored) and route execution (on-demand)
// preserves the event-storage / route-execution distinction from the spec.

/// The type of Gas Town entity that originated the notification.
///
/// Each case carries enough identity to route back to the originating
/// context via ``OpenRouter``.
enum NotificationOrigin: Equatable, Sendable {
    /// Originated from a specific agent (polecat, crew member, etc.).
    ///
    /// - Parameter address: Canonical agent address (e.g. `"gmux/polecats/chrome"`).
    case agent(address: String)

    /// Originated from a bead (issue, task, bug).
    ///
    /// - Parameters:
    ///   - beadID: The bead identifier (e.g. `"gm-3rs"`).
    ///   - assignee: Pre-fetched assignee data, if available at event time.
    case bead(beadID: String, assignee: BeadAssignee?)

    /// Originated from a convoy (batched multi-rig work).
    ///
    /// - Parameters:
    ///   - convoyID: The convoy identifier (e.g. `"hq-cv-abc12"`).
    ///   - trackedBeads: Pre-fetched tracked beads, if available at event time.
    case convoy(convoyID: String, trackedBeads: [ConvoyTrackedBead])
}

/// Structured context attached to a notification or event.
///
/// Immutable, value-typed, and ``Sendable`` so it can be stored alongside
/// notifications and consumed later when the user interacts with the alert.
///
/// **Storage contract:** This struct is stored as part of the notification
/// payload.  Route execution happens on-demand when the user taps/clicks
/// the notification, via ``NotificationRouter``.
struct NotificationContext: Equatable, Sendable {
    /// The routing origin -- which entity produced this event.
    let origin: NotificationOrigin

    /// Optional convoy context ID for workspace binding.
    ///
    /// Present when the event is convoy-scoped or the originating bead
    /// belongs to a tracked convoy.
    let convoyID: String?

    /// Optional bead context ID for workspace binding.
    ///
    /// Present when the event references a specific bead.
    let beadID: String?

    /// The rig this event belongs to, if known.
    let rigID: String?
}

// MARK: - Convenience Factories

extension NotificationContext {
    /// Create a context for an agent-originated event.
    ///
    /// - Parameters:
    ///   - address: Canonical agent address.
    ///   - convoyID: Optional convoy this agent is working on.
    ///   - beadID: Optional bead this agent is working on.
    ///   - rigID: The rig the agent belongs to.
    static func fromAgent(
        address: String,
        convoyID: String? = nil,
        beadID: String? = nil,
        rigID: String? = nil
    ) -> NotificationContext {
        NotificationContext(
            origin: .agent(address: address),
            convoyID: convoyID,
            beadID: beadID,
            rigID: rigID
        )
    }

    /// Create a context for a bead-originated event.
    ///
    /// - Parameters:
    ///   - beadID: The bead identifier.
    ///   - assignee: Pre-fetched assignee, if known.
    ///   - convoyID: Optional convoy tracking this bead.
    ///   - rigID: The rig this bead belongs to.
    static func fromBead(
        beadID: String,
        assignee: BeadAssignee? = nil,
        convoyID: String? = nil,
        rigID: String? = nil
    ) -> NotificationContext {
        NotificationContext(
            origin: .bead(beadID: beadID, assignee: assignee),
            convoyID: convoyID,
            beadID: beadID,
            rigID: rigID
        )
    }

    /// Create a context for a convoy-originated event.
    ///
    /// - Parameters:
    ///   - convoyID: The convoy identifier.
    ///   - trackedBeads: Pre-fetched tracked beads, if available.
    ///   - rigID: The primary rig, if the convoy is rig-scoped.
    static func fromConvoy(
        convoyID: String,
        trackedBeads: [ConvoyTrackedBead] = [],
        rigID: String? = nil
    ) -> NotificationContext {
        NotificationContext(
            origin: .convoy(convoyID: convoyID, trackedBeads: trackedBeads),
            convoyID: convoyID,
            beadID: nil,
            rigID: rigID
        )
    }
}

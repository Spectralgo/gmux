import Foundation

// MARK: - Notification Jump Target
//
// The result of resolving a ``NotificationContext`` into a routable intent.
// Carries the ``OpenIntent`` plus metadata about the resolution for logging,
// analytics, and UI display.
//
// Consumed by ``OpenIntentExecuting`` implementations to open the correct
// workspace, and by notification UI to show contextual information (e.g.
// "Jump to gmux/polecats/chrome" in the notification action).

/// A resolved jump target from a notification or event.
///
/// Wraps an ``OpenIntent`` with the originating context and resolution
/// metadata.  This is the output type of ``NotificationRouter`` -- all
/// consumers (notification click handlers, mail inbox, socket commands)
/// receive the same structure.
struct NotificationJumpTarget: Equatable {
    /// The resolved open intent to execute.
    let intent: OpenIntent

    /// The context that was resolved to produce this target.
    let source: NotificationContext

    /// Human-readable label for UI display (e.g. button text).
    ///
    /// Derived from the intent label and origin type. Suitable for
    /// localized display in notification actions and the inbox.
    let displayLabel: String

    /// Whether this target was fully resolved (has a worktree path).
    ///
    /// A partially-resolved target (e.g. convoy with no actionable beads)
    /// opens a dashboard view instead of a specific terminal workspace.
    var isFullyResolved: Bool {
        intent.target.resolvedWorktree != nil
    }
}

/// Errors from resolving a ``NotificationContext`` into a jump target.
///
/// These are routing-layer errors, not UI errors. The notification UI
/// should degrade gracefully (e.g. hide the "Jump" button) rather than
/// showing raw error text.
enum NotificationRoutingError: Error, Equatable {
    /// The notification has no routing context attached.
    case noContext

    /// The underlying ``OpenRouter`` could not resolve the target.
    ///
    /// Wraps the ``OpenRoutingError`` for programmatic handling.
    case routingFailed(OpenRoutingError)

    /// The bead referenced by the notification has no assignee.
    case beadNotAssigned(beadID: String)

    /// A localized description suitable for debug logging.
    var debugDescription: String {
        switch self {
        case .noContext:
            return "Notification has no routing context"
        case .routingFailed(let inner):
            return "Routing failed: \(inner)"
        case .beadNotAssigned(let beadID):
            return "Bead \(beadID) has no assignee for routing"
        }
    }
}

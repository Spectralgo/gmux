import Foundation

// MARK: - Notification Router
//
// Maps notification/event contexts into executable jump targets by
// composing with ``OpenRouter`` (TASK-010) routing primitives.
//
// Design principles:
//   - Stateless (caseless enum with static methods), same as ``OpenRouter``.
//   - Never shells out to processes or touches the filesystem.
//   - Callers pre-fetch all required data (assignees, tracked beads, rig snapshot).
//   - Focus policy is explicit: notification arrivals are `.silent`,
//     user-initiated jumps are `.focusful`.
//   - Preserves the event-storage / route-execution split: contexts are
//     stored with notifications, routing happens on-demand here.
//
// Reusable by: mail inbox, operator dashboard, socket `notification.open`
// command, and future MCP notification surfaces.

/// Routes ``NotificationContext`` values into ``NotificationJumpTarget`` values.
///
/// This is the bridge between the notification/event storage layer and the
/// open-routing layer. It composes with ``OpenRouter`` for identity resolution
/// and adds notification-specific focus policy and display label derivation.
///
/// **Threading:** All methods are synchronous and thread-safe (pure functions
/// over value types). Focus policy enforcement happens downstream in
/// ``OpenIntentExecuting``.
enum NotificationRouter {

    // MARK: - Primary API

    /// Resolve a notification context into a jump target.
    ///
    /// Routes through ``OpenRouter`` based on the context's origin type:
    /// - `.agent` -> ``OpenRouter.routeByAgent``
    /// - `.bead` -> ``OpenRouter.routeByBead``
    /// - `.convoy` -> ``OpenRouter.routeByConvoy``
    ///
    /// - Parameters:
    ///   - context: The notification context to resolve.
    ///   - snapshot: Current rig inventory for identity resolution.
    ///   - focus: Focus behavior. Defaults to `.focusful` (user clicked).
    ///     Use `.silent` for background pre-resolution.
    /// - Returns: A ``NotificationJumpTarget`` ready for execution.
    /// - Throws: ``NotificationRoutingError`` if the context cannot be resolved.
    static func resolve(
        context: NotificationContext,
        in snapshot: RigInventorySnapshot,
        focus: FocusPolicy = .focusful
    ) throws -> NotificationJumpTarget {
        let intent: OpenIntent
        let displayLabel: String

        switch context.origin {
        case .agent(let address):
            intent = try routeAgent(address: address, snapshot: snapshot, focus: focus)
            displayLabel = labelForAgent(address)

        case .bead(let beadID, let assignee):
            intent = try routeBead(beadID: beadID, assignee: assignee, snapshot: snapshot, focus: focus)
            displayLabel = labelForBead(beadID)

        case .convoy(let convoyID, let trackedBeads):
            intent = try routeConvoy(convoyID: convoyID, trackedBeads: trackedBeads, snapshot: snapshot, focus: focus)
            displayLabel = labelForConvoy(convoyID)
        }

        return NotificationJumpTarget(
            intent: intent,
            source: context,
            displayLabel: displayLabel
        )
    }

    /// Attempt to resolve a context, returning `nil` instead of throwing.
    ///
    /// Useful for UI code that wants to conditionally show a "Jump" button
    /// without try/catch boilerplate.
    static func tryResolve(
        context: NotificationContext,
        in snapshot: RigInventorySnapshot,
        focus: FocusPolicy = .focusful
    ) -> NotificationJumpTarget? {
        try? resolve(context: context, in: snapshot, focus: focus)
    }

    // MARK: - Focus Policy Helpers

    /// The default focus policy for notification arrival (background event).
    ///
    /// Notifications arriving in the background should NOT steal focus.
    /// This preserves the socket focus policy documented in CLAUDE.md.
    static let arrivalFocusPolicy: FocusPolicy = .silent

    /// The default focus policy for user-initiated notification interaction.
    ///
    /// When the user clicks a notification, the target workspace should
    /// be focused. This is an explicit focus-intent command.
    static let interactionFocusPolicy: FocusPolicy = .focusful

    // MARK: - Private Routing

    private static func routeAgent(
        address: String,
        snapshot: RigInventorySnapshot,
        focus: FocusPolicy
    ) throws -> OpenIntent {
        do {
            return try OpenRouter.routeByAgent(address: address, in: snapshot, focus: focus)
        } catch let error as OpenRoutingError {
            throw NotificationRoutingError.routingFailed(error)
        }
    }

    private static func routeBead(
        beadID: String,
        assignee: BeadAssignee?,
        snapshot: RigInventorySnapshot,
        focus: FocusPolicy
    ) throws -> OpenIntent {
        guard let assignee else {
            throw NotificationRoutingError.beadNotAssigned(beadID: beadID)
        }
        do {
            return try OpenRouter.routeByBead(
                beadID: beadID,
                assignee: assignee,
                in: snapshot,
                focus: focus
            )
        } catch let error as OpenRoutingError {
            throw NotificationRoutingError.routingFailed(error)
        }
    }

    private static func routeConvoy(
        convoyID: String,
        trackedBeads: [ConvoyTrackedBead],
        snapshot: RigInventorySnapshot,
        focus: FocusPolicy
    ) throws -> OpenIntent {
        do {
            return try OpenRouter.routeByConvoy(
                convoyID: convoyID,
                trackedBeads: trackedBeads,
                in: snapshot,
                focus: focus
            )
        } catch let error as OpenRoutingError {
            throw NotificationRoutingError.routingFailed(error)
        }
    }

    // MARK: - Display Labels

    private static func labelForAgent(_ address: String) -> String {
        let components = address.split(separator: "/")
        if components.count >= 3 {
            return String(components.last!)
        }
        return address
    }

    private static func labelForBead(_ beadID: String) -> String {
        beadID
    }

    private static func labelForConvoy(_ convoyID: String) -> String {
        convoyID
    }
}

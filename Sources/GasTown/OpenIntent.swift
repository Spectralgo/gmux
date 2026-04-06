import Foundation

/// A resolved instruction to open or focus a workspace context.
///
/// Produced by ``OpenRouter`` routing primitives, consumed by
/// ``OpenIntentExecutor`` and downstream features (CLI, socket, MCP).
///
/// This is the single output type of the routing layer. All consumers
/// receive the same structure regardless of whether the intent originated
/// from a UI click, a socket command, or a notification.
struct OpenIntent: Equatable {
    /// What to open -- the resolved target.
    let target: OpenTarget

    /// Focus behavior for this intent.
    let focusPolicy: FocusPolicy

    /// Display label for the workspace (e.g. `"gmux/polecats/chrome"`).
    let label: String?

    /// Optional convoy context to bind to the workspace.
    let convoyContext: String?

    /// Optional bead context to bind to the workspace.
    let beadContext: String?
}

/// The resolved target for an open action.
///
/// Each case carries the resolved worktree (when available) so that
/// the executor knows where to set the working directory.
enum OpenTarget: Equatable {
    /// Open a resolved agent worktree.
    ///
    /// Source: ``AgentIdentityResolver`` (TASK-009).
    case agent(ResolvedWorktree)

    /// Open a bead's assigned agent worktree.
    ///
    /// Resolves bead -> assignee agent -> worktree.
    case bead(beadID: String, resolvedWorktree: ResolvedWorktree)

    /// Open a convoy context.
    ///
    /// When the convoy has an actionable bead with an assignee, the
    /// worktree is resolved. When no actionable bead exists, the
    /// worktree is `nil` and the executor opens a convoy dashboard.
    case convoy(convoyID: String, resolvedWorktree: ResolvedWorktree?)

    /// The resolved worktree, if available.
    var resolvedWorktree: ResolvedWorktree? {
        switch self {
        case .agent(let wt): return wt
        case .bead(_, let wt): return wt
        case .convoy(_, let wt): return wt
        }
    }

    /// A stable string key for workspace binding and deduplication.
    ///
    /// Two intents with the same `bindingKey` should reuse the same workspace.
    var bindingKey: String {
        switch self {
        case .agent(let wt):
            return "agent:\(wt.identity.address)"
        case .bead(let beadID, _):
            return "bead:\(beadID)"
        case .convoy(let convoyID, _):
            return "convoy:\(convoyID)"
        }
    }
}

/// Controls whether an open action activates the window and steals focus.
///
/// Maps to cmux's existing `withSocketCommandPolicy()` pattern and the
/// socket focus policy documented in CLAUDE.md.
enum FocusPolicy: String, Equatable, Codable {
    /// Activate the window, select the workspace, focus the pane.
    ///
    /// Used by: explicit user navigation (click, CLI with `--focus`).
    case focusful

    /// Create or find the workspace but do NOT activate window or steal focus.
    ///
    /// Used by: notifications, background opens, automation without `--focus`.
    case silent

    /// Focus if the workspace already exists; create silently if new.
    ///
    /// Used by: "ensure open" patterns where re-focus is expected but
    /// new workspace creation should not interrupt.
    case focusIfExists
}

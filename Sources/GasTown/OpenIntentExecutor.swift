import Foundation

/// The result of executing an ``OpenIntent``.
struct OpenResult: Equatable {
    /// The workspace ID that was opened or reused.
    let workspaceID: UUID

    /// Whether a new workspace was created (vs. reusing an existing one).
    let isNew: Bool

    /// Whether focus was applied (window activated, workspace selected).
    let focusApplied: Bool

    /// The binding key used for workspace deduplication.
    let bindingKey: String
}

/// Executes ``OpenIntent`` values by creating, finding, or focusing workspaces.
///
/// This is the bridge between the domain routing layer (``OpenRouter``) and
/// the app's workspace management (TabManager, AppDelegate). It is the ONLY
/// type in the routing stack that touches UI state.
///
/// Conforming types run on the main actor because workspace mutations require
/// AppKit coordination.
///
/// **Workspace binding:** When an intent creates a new workspace, the executor
/// tags it with ``OpenTarget/bindingKey`` so that subsequent intents for the
/// same target reuse the workspace instead of creating duplicates.
@MainActor
protocol OpenIntentExecuting {
    /// Execute an open intent.
    ///
    /// If a workspace already exists for the intent's target (matched by
    /// ``OpenTarget/bindingKey``), the executor reuses it. Otherwise it
    /// creates a new workspace at the resolved worktree path.
    ///
    /// Focus behavior is governed by the intent's ``FocusPolicy``:
    /// - `.focusful`: activate window, select workspace, focus terminal pane.
    /// - `.silent`: create/find workspace, do not activate or steal focus.
    /// - `.focusIfExists`: focus if reusing, silent if creating new.
    ///
    /// - Parameter intent: The open intent to execute.
    /// - Returns: An ``OpenResult`` describing what happened.
    func execute(_ intent: OpenIntent) -> OpenResult

    /// Find an existing workspace bound to the given target, if any.
    ///
    /// This is a read-only query that does not modify workspace state.
    /// Useful for checking "is this agent already open?" before deciding
    /// whether to route.
    ///
    /// - Parameter target: The open target to search for.
    /// - Returns: The workspace ID if a bound workspace exists.
    func findExisting(for target: OpenTarget) -> UUID?
}

/// Storage for workspace-to-routing-target bindings.
///
/// Maintains a bidirectional mapping between workspace IDs and their
/// ``OpenTarget/bindingKey`` strings. Used by ``OpenIntentExecuting``
/// implementations to deduplicate workspace creation.
///
/// This type is separate from the executor so that it can be shared
/// across app components (e.g. workspace close handlers that need to
/// clean up bindings).
final class WorkspaceBindingStore {
    /// Maps binding keys to workspace IDs.
    private var keyToWorkspace: [String: UUID] = [:]

    /// Maps workspace IDs to binding keys.
    private var workspaceToKey: [UUID: String] = [:]

    /// Bind a workspace to a routing target key.
    func bind(workspaceID: UUID, to key: String) {
        // Remove any existing binding for this workspace.
        if let oldKey = workspaceToKey[workspaceID] {
            keyToWorkspace.removeValue(forKey: oldKey)
        }
        // Remove any existing workspace for this key.
        if let oldWorkspace = keyToWorkspace[key] {
            workspaceToKey.removeValue(forKey: oldWorkspace)
        }
        keyToWorkspace[key] = workspaceID
        workspaceToKey[workspaceID] = key
    }

    /// Find the workspace bound to a key, if any.
    func workspace(for key: String) -> UUID? {
        keyToWorkspace[key]
    }

    /// Find the key bound to a workspace, if any.
    func key(for workspaceID: UUID) -> String? {
        workspaceToKey[workspaceID]
    }

    /// Remove the binding for a workspace (e.g. when the workspace closes).
    func unbind(workspaceID: UUID) {
        if let key = workspaceToKey.removeValue(forKey: workspaceID) {
            keyToWorkspace.removeValue(forKey: key)
        }
    }

    /// Remove all bindings.
    func removeAll() {
        keyToWorkspace.removeAll()
        workspaceToKey.removeAll()
    }
}

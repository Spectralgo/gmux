import Foundation

// MARK: - Open Intent

/// A typed description of what the user or automation wants to open.
/// Intents are resolved by ``OpenRouter`` into concrete workspace actions.
enum OpenIntent {
    /// Open a workspace rooted at a filesystem directory.
    case directory(path: String, preset: WorkspacePreset?)

    /// Open the workspace associated with a convoy (worktree group).
    case convoy(id: String, workingDirectory: String?, preset: WorkspacePreset?)

    /// Open the workspace associated with a bead (issue/work item).
    case bead(id: String, workingDirectory: String?, preset: WorkspacePreset?)

    /// Open the workspace for a specific agent (rig/polecat).
    case agent(rig: String, name: String?, workingDirectory: String?, preset: WorkspacePreset?)

    /// Jump to an existing notification's workspace context.
    case notification(id: UUID, tabId: UUID, surfaceId: UUID?)
}

extension OpenIntent {
    /// The working directory associated with this intent, if any.
    var workingDirectory: String? {
        switch self {
        case .directory(let path, _):
            return path
        case .convoy(_, let dir, _), .bead(_, let dir, _), .agent(_, _, let dir, _):
            return dir
        case .notification:
            return nil
        }
    }

    /// The explicit preset requested, if any.
    var preset: WorkspacePreset? {
        switch self {
        case .directory(_, let p), .convoy(_, _, let p), .bead(_, _, let p), .agent(_, _, _, let p):
            return p
        case .notification:
            return nil
        }
    }

    /// A stable string key for matching this intent to an existing workspace.
    /// Used by ``OpenRouter`` to avoid duplicating workspaces for the same context.
    var matchKey: String? {
        switch self {
        case .directory(let path, _):
            return "dir:\(path)"
        case .convoy(let id, _, _):
            return "convoy:\(id)"
        case .bead(let id, _, _):
            return "bead:\(id)"
        case .agent(let rig, let name, _, _):
            if let name {
                return "agent:\(rig)/\(name)"
            }
            return "agent:\(rig)"
        case .notification(_, let tabId, _):
            return "tab:\(tabId.uuidString)"
        }
    }
}

// MARK: - Open Intent Options

/// Controls how the router executes an open intent.
struct OpenIntentOptions {
    /// Whether the action may steal macOS app focus (activate/raise window).
    var allowFocus: Bool = true

    /// Whether to flash the destination pane after focusing.
    var flash: Bool = false

    /// Where to place the new workspace when creating one.
    var placement: OpenIntentPlacement = .tab

    /// Optional title override for the created workspace.
    var title: String?

    /// Optional description for the created workspace.
    var description: String?

    static let `default` = OpenIntentOptions()

    /// Non-focus options: applies model/data changes without stealing focus.
    static let silent = OpenIntentOptions(allowFocus: false, flash: false)
}

/// Where a newly created workspace should appear.
enum OpenIntentPlacement {
    /// As a new tab/workspace in the current window.
    case tab
    /// In a new window.
    case window
}

// MARK: - Open Intent Result

/// The outcome of executing an ``OpenIntent`` through the router.
struct OpenIntentResult {
    let workspaceId: UUID
    let windowId: UUID?
    let createdWorkspace: Bool
    let appliedPreset: WorkspacePreset?
}

// MARK: - Workspace Preset

/// A named pane composition that describes the layout to create or restore
/// when opening a workspace for a specific context type.
///
/// Presets are intentionally coarse — they describe the *kind* of layout,
/// not pixel-level geometry. The router maps them to concrete split/panel
/// operations via ``WorkspacePreset/apply(to:in:)``.
enum WorkspacePreset: String, Codable, CaseIterable {
    /// Single terminal pane (default for most contexts).
    case terminal

    /// Terminal on the left, browser split on the right.
    /// Good for agent/bead contexts where docs or web UI are relevant.
    case terminalBrowser

    /// Two terminal panes side by side (horizontal split).
    /// Useful for comparing outputs or watching logs alongside work.
    case dualTerminal

    /// Single browser pane.
    case browser
}

extension WorkspacePreset {
    /// Human-readable label for UI display.
    var displayName: String {
        switch self {
        case .terminal: return String(localized: "preset.terminal", defaultValue: "Terminal")
        case .terminalBrowser: return String(localized: "preset.terminalBrowser", defaultValue: "Terminal + Browser")
        case .dualTerminal: return String(localized: "preset.dualTerminal", defaultValue: "Dual Terminal")
        case .browser: return String(localized: "preset.browser", defaultValue: "Browser")
        }
    }
}

// MARK: - Context-to-Preset Mapping

/// Maps known context types to their default workspace preset.
///
/// This is the central place to change which layout a context jump creates.
/// UI and automation surfaces should call ``defaultPreset(for:)`` rather than
/// hard-coding preset choices.
enum ContextPresetMapping {
    /// Returns the default preset for the given intent type when no explicit
    /// preset is specified.
    static func defaultPreset(for intent: OpenIntent) -> WorkspacePreset {
        switch intent {
        case .directory:
            return .terminal
        case .convoy:
            return .terminal
        case .bead:
            return .terminal
        case .agent:
            return .terminal
        case .notification:
            return .terminal
        }
    }
}

// MARK: - Notification Context

/// Optional structured context attached to a notification, enabling
/// context-aware jump targets instead of bare tab/surface IDs.
struct NotificationContext: Hashable {
    /// The type of context this notification relates to.
    var contextType: ContextType?

    /// The identifier within that context (convoy ID, bead ID, agent path).
    var contextId: String?

    /// The working directory associated with the context, if known.
    var workingDirectory: String?

    /// The preset to use when jumping to this notification's context.
    var preset: WorkspacePreset?

    enum ContextType: String, Hashable, Codable {
        case convoy
        case bead
        case agent
        case directory
    }

    /// Build an ``OpenIntent`` from this notification context, falling back
    /// to the notification's tab/surface IDs when context is insufficient.
    func openIntent(notificationId: UUID, tabId: UUID, surfaceId: UUID?) -> OpenIntent {
        guard let contextType, let contextId else {
            return .notification(id: notificationId, tabId: tabId, surfaceId: surfaceId)
        }
        switch contextType {
        case .convoy:
            return .convoy(id: contextId, workingDirectory: workingDirectory, preset: preset)
        case .bead:
            return .bead(id: contextId, workingDirectory: workingDirectory, preset: preset)
        case .agent:
            let parts = contextId.split(separator: "/", maxSplits: 1)
            let rig = String(parts.first ?? "")
            let name = parts.count > 1 ? String(parts[1]) : nil
            return .agent(rig: rig, name: name, workingDirectory: workingDirectory, preset: preset)
        case .directory:
            return .directory(path: contextId, preset: preset)
        }
    }
}

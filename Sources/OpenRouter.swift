import Foundation
import AppKit

// MARK: - Open Router

/// Resolves ``OpenIntent`` values into concrete workspace actions.
///
/// The router is the single entry point for all contextual open flows.
/// UI actions, socket commands, and notification jumps all route through here,
/// ensuring consistent behavior for focus policy, workspace reuse, and
/// preset application.
///
/// **Threading:** All methods must be called on the main thread.
@MainActor
final class OpenRouter {

    private let tabManagerProvider: () -> TabManager?
    private let appDelegateProvider: () -> AppDelegate?

    init(
        tabManagerProvider: @escaping () -> TabManager?,
        appDelegateProvider: @escaping () -> AppDelegate?
    ) {
        self.tabManagerProvider = tabManagerProvider
        self.appDelegateProvider = appDelegateProvider
    }

    /// Convenience initializer using default singletons.
    convenience init() {
        self.init(
            tabManagerProvider: { AppDelegate.shared?.tabManager },
            appDelegateProvider: { AppDelegate.shared }
        )
    }

    // MARK: - Public API

    /// Execute an open intent, creating or focusing the appropriate workspace.
    ///
    /// - Parameters:
    ///   - intent: What to open.
    ///   - options: How to execute the open (focus policy, placement, etc.).
    /// - Returns: The result describing what happened, or nil if the action failed.
    @discardableResult
    func open(_ intent: OpenIntent, options: OpenIntentOptions = .default) -> OpenIntentResult? {
        // For notification intents, delegate to the existing notification focus path.
        if case .notification(_, let tabId, let surfaceId) = intent {
            return openNotification(tabId: tabId, surfaceId: surfaceId, options: options)
        }

        guard let tabManager = tabManagerProvider() else { return nil }

        // Step 1: Try to find an existing workspace that matches this intent.
        if let existingResult = focusExistingWorkspace(
            for: intent,
            in: tabManager,
            options: options
        ) {
            return existingResult
        }

        // Step 2: Create a new workspace for this intent.
        return createWorkspace(for: intent, in: tabManager, options: options)
    }

    // MARK: - Workspace Matching

    /// Search existing workspaces for one that matches the intent's context.
    private func focusExistingWorkspace(
        for intent: OpenIntent,
        in tabManager: TabManager,
        options: OpenIntentOptions
    ) -> OpenIntentResult? {
        guard let matchKey = intent.matchKey else { return nil }

        // Match by context tag first (set by previous open-intent actions).
        if let workspace = tabManager.tabs.first(where: {
            $0.openIntentContextTag == matchKey
        }) {
            focusWorkspace(workspace, in: tabManager, options: options)
            return OpenIntentResult(
                workspaceId: workspace.id,
                windowId: nil,
                createdWorkspace: false,
                appliedPreset: nil
            )
        }

        // Fall back to directory matching for directory-based intents.
        if let dir = intent.workingDirectory {
            let normalizedDir = (dir as NSString).expandingTildeInPath
            if let workspace = tabManager.tabs.first(where: {
                $0.currentDirectory == normalizedDir
            }) {
                focusWorkspace(workspace, in: tabManager, options: options)
                return OpenIntentResult(
                    workspaceId: workspace.id,
                    windowId: nil,
                    createdWorkspace: false,
                    appliedPreset: nil
                )
            }
        }

        return nil
    }

    // MARK: - Workspace Creation

    /// Create a new workspace and apply the appropriate preset.
    private func createWorkspace(
        for intent: OpenIntent,
        in tabManager: TabManager,
        options: OpenIntentOptions
    ) -> OpenIntentResult? {
        let dir = intent.workingDirectory
        let preset = intent.preset ?? ContextPresetMapping.defaultPreset(for: intent)
        let shouldSelect = options.allowFocus

        switch options.placement {
        case .tab:
            let workspace = tabManager.addWorkspace(
                title: options.title,
                workingDirectory: dir,
                select: shouldSelect
            )
            workspace.openIntentContextTag = intent.matchKey
            if let desc = options.description {
                workspace.setCustomDescription(desc)
            }
            applyPreset(preset, to: workspace, in: tabManager)
            if options.allowFocus {
                activateApp()
            }
            return OpenIntentResult(
                workspaceId: workspace.id,
                windowId: nil,
                createdWorkspace: true,
                appliedPreset: preset
            )

        case .window:
            guard let app = appDelegateProvider() else { return nil }
            let windowId = app.createMainWindow(initialWorkingDirectory: dir)
            // After window creation, find the workspace and apply preset.
            if let newTabManager = app.tabManagerFor(windowId: windowId),
               let workspace = newTabManager.tabs.first {
                workspace.openIntentContextTag = intent.matchKey
                if let title = options.title {
                    workspace.customTitle = title
                }
                if let desc = options.description {
                    workspace.setCustomDescription(desc)
                }
                applyPreset(preset, to: workspace, in: newTabManager)
            }
            return OpenIntentResult(
                workspaceId: UUID(),
                windowId: windowId,
                createdWorkspace: true,
                appliedPreset: preset
            )
        }
    }

    // MARK: - Preset Application

    /// Apply a workspace preset to configure the pane layout.
    ///
    /// Presets compose with the existing TabManager split/browser APIs.
    /// Each preset is a recipe of split and panel operations applied
    /// to a freshly created workspace.
    private func applyPreset(
        _ preset: WorkspacePreset,
        to workspace: Workspace,
        in tabManager: TabManager
    ) {
        switch preset {
        case .terminal:
            // Default single-terminal layout — nothing extra to do.
            break

        case .terminalBrowser:
            // Split right and open a browser in the new pane.
            tabManager.openBrowser(
                inWorkspace: workspace.id,
                url: nil,
                preferSplitRight: true
            )

        case .dualTerminal:
            // Create a horizontal split from the initial terminal pane.
            if let firstPanelId = workspace.focusedPanelId ?? workspace.panels.keys.first {
                _ = tabManager.newSplit(
                    tabId: workspace.id,
                    surfaceId: firstPanelId,
                    direction: .right,
                    focus: false
                )
            }

        case .browser:
            // Open a browser in the existing pane (replaces terminal tab).
            tabManager.openBrowser(
                inWorkspace: workspace.id,
                url: nil,
                preferSplitRight: false
            )
        }
    }

    // MARK: - Focus Helpers

    private func focusWorkspace(
        _ workspace: Workspace,
        in tabManager: TabManager,
        options: OpenIntentOptions
    ) {
        guard options.allowFocus else { return }
        tabManager.focusTab(
            workspace.id,
            surfaceId: nil,
            suppressFlash: !options.flash
        )
    }

    private func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.unhide(nil)
    }

    // MARK: - Notification Intent

    private func openNotification(
        tabId: UUID,
        surfaceId: UUID?,
        options: OpenIntentOptions
    ) -> OpenIntentResult? {
        guard let tabManager = tabManagerProvider() else { return nil }
        guard options.allowFocus else { return nil }

        let success = tabManager.focusTabFromNotification(tabId, surfaceId: surfaceId)
        guard success else { return nil }

        return OpenIntentResult(
            workspaceId: tabId,
            windowId: nil,
            createdWorkspace: false,
            appliedPreset: nil
        )
    }
}

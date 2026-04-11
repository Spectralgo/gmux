import Foundation
import SwiftUI
import Combine

/// Panel showing the merge pipeline queue for a rig's refinery.
///
/// Phase 1: Read-only queue list with load state, silent auto-refresh,
/// and basic queue item cards. No action commands, no socket events,
/// no build log viewer.
///
/// Follows the same load/refresh pattern as ``RigPanel``:
/// - Initial load on `.onAppear`
/// - Auto-refresh via `GasTownService.shared.$refreshTick` (8s)
/// - Silent refresh skips `.loading` state and only publishes on change
@MainActor
final class RefineryPanel: Panel, ObservableObject {
    let id: UUID
    let panelType: PanelType = .refinery

    @Published private(set) var displayTitle: String = String(
        localized: "refineryPanel.title",
        defaultValue: "Merge Pipeline"
    )
    @Published private(set) var loadState: RefineryLoadState = .idle

    /// Currently selected queue item (for future expansion).
    @Published var selectedItemId: String?

    /// Token incremented to trigger focus flash animation.
    @Published private(set) var focusFlashToken: Int = 0

    var displayIcon: String? { GasTownRoleIcons.refinery }

    /// The rig this panel displays.
    let rigId: String

    /// Workspace that owns this panel.
    let workspaceId: UUID

    /// Data adapter for loading refinery data.
    private let adapter: RefineryAdapter

    /// Tick counter for refresh cadence.
    private var tickCounter: Int = 0

    init(rigId: String, workspaceId: UUID, adapter: RefineryAdapter) {
        self.id = UUID()
        self.rigId = rigId
        self.workspaceId = workspaceId
        self.adapter = adapter
    }

    // MARK: - Panel protocol

    func focus() {}
    func unfocus() {}
    func close() {}

    func triggerFlash(reason: WorkspaceAttentionFlashReason) {
        _ = reason
        guard NotificationPaneFlashSettings.isEnabled() else { return }
        focusFlashToken += 1
    }

    // MARK: - Data Loading

    /// Load refinery data. Runs CLI calls off-main, publishes on main.
    ///
    /// - Parameter silent: When `true` (auto-refresh), skips `.loading` state
    ///   and only publishes if data changed.
    func refresh(silent: Bool = false) {
        if !silent {
            loadState = .loading
        }

        let adapter = self.adapter
        let rigId = self.rigId

        if silent {
            tickCounter += 1
        } else {
            tickCounter = 0
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = adapter.loadSnapshot(rigId: rigId)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let snapshot):
                    let newState = RefineryLoadState.loaded(snapshot)
                    if self.loadState != newState {
                        self.loadState = newState
                    }
                case .failure(let error):
                    let newState = RefineryLoadState.failed(error)
                    if self.loadState != newState {
                        self.loadState = newState
                    }
                }
            }
        }
    }
}

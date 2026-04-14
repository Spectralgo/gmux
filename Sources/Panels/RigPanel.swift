import Foundation
import SwiftUI
import Combine

/// Panel showing a single rig's team, work, health, and configuration.
///
/// Follows the same load/refresh pattern as ``TownDashboardPanel``:
/// - Initial load on `.onAppear`
/// - Auto-refresh via `GasTownService.shared.$refreshTick` (8s)
/// - Silent refresh skips `.loading` state and only publishes on change
/// - Health indicators refresh on a slower cadence (every 3rd tick = 24s)
@MainActor
final class RigPanel: Panel, ObservableObject {
    let id: UUID
    let panelType: PanelType = .rigPanel

    @Published private(set) var displayTitle: String
    @Published private(set) var loadState: RigPanelLoadState = .idle

    /// Whether infrastructure agents (refinery, witness, deacon) are collapsed.
    @Published var infrastructureCollapsed: Bool = true

    /// Which health row is expanded for detail (keyed by indicator name).
    @Published var expandedHealthRow: String?

    /// Token incremented to trigger focus flash animation.
    @Published private(set) var focusFlashToken: Int = 0

    /// Action result toast (auto-dismisses after 4s).
    @Published var actionResult: GasTownActionResult?

    var displayIcon: String? { "folder.badge.gearshape" }

    /// The rig this panel displays.
    let rigId: String

    /// Workspace that owns this panel.
    let workspaceId: UUID

    /// Data adapter for loading rig data.
    private let adapter: RigPanelAdapter

    /// Tick counter for health cadence (refresh health every 3rd tick).
    private(set) var tickCounter: Int = 0

    init(rigId: String, workspaceId: UUID, adapter: RigPanelAdapter) {
        self.id = UUID()
        self.rigId = rigId
        self.workspaceId = workspaceId
        self.adapter = adapter
        self.displayTitle = rigId
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

    // MARK: - Role Grouping

    /// Group agents by role category, ordered by AgentRoleGroup case order.
    func groupedAgents(from agents: [AgentHealthEntry]) -> [(group: AgentRoleGroup, agents: [AgentHealthEntry])] {
        let grouped = Dictionary(grouping: agents) { AgentRoleGroup.from(role: $0.role) }
        return AgentRoleGroup.allCases.compactMap { group in
            guard let agents = grouped[group], !agents.isEmpty else { return nil }
            return (group: group, agents: agents)
        }
    }

    // MARK: - Data Loading

    /// Load all rig panel data. Runs CLI calls off-main, publishes on main.
    ///
    /// - Parameter silent: When `true` (auto-refresh), skips `.loading` state
    ///   and only publishes if data changed.
    func refresh(silent: Bool = false) {
        if !silent {
            loadState = .loading
        }

        let adapter = self.adapter
        let rigId = self.rigId
        let includeHealth: Bool

        // Health indicators on slower cadence (every 3rd tick = 24s)
        if silent {
            tickCounter += 1
            includeHealth = tickCounter % 3 == 0
        } else {
            tickCounter = 0
            includeHealth = true
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<RigPanelSnapshot, RigPanelAdapterError>
            if includeHealth {
                result = adapter.loadSnapshot(rigId: rigId)
            } else {
                result = adapter.loadLightSnapshot(rigId: rigId)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .success(var snapshot):
                    // On light refresh, preserve existing health indicators
                    if !includeHealth, case .loaded(let existing) = self.loadState {
                        snapshot = RigPanelSnapshot(
                            rig: snapshot.rig,
                            agents: snapshot.agents,
                            beadCounts: snapshot.beadCounts,
                            convoys: snapshot.convoys,
                            healthIndicators: existing.healthIndicators
                        )
                    }
                    let newState = RigPanelLoadState.loaded(snapshot)
                    if self.loadState != newState {
                        self.loadState = newState
                    }
                case .failure(let error):
                    let newState = RigPanelLoadState.failed(error)
                    if self.loadState != newState {
                        self.loadState = newState
                    }
                }
            }
        }
    }

    /// Spawn a new polecat in this rig via socket handler.
    func spawnPolecat() {
        let rigId = self.rigId
        Task {
            let result = await GastownSocketHandlers.gastownPolecatSpawn(params: ["rig": rigId])
            switch result {
            case .ok:
                showActionResult(.success(String(
                    localized: "rigPanel.action.spawnSuccess",
                    defaultValue: "Polecat spawned in \(rigId)"
                )))
                refresh(silent: true)
            case .err(_, let message):
                showActionResult(.failure(message))
            }
        }
    }

    // MARK: - Action Result Toast

    /// Show an action result toast that auto-dismisses after 4 seconds.
    func showActionResult(_ result: GasTownActionResult) {
        withAnimation(GasTownAnimation.statusChange) {
            actionResult = result
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.actionResult == result else { return }
            withAnimation(GasTownAnimation.statusChange) {
                self.actionResult = nil
            }
        }
    }

    /// Toggle expansion of a health row by indicator name.
    func toggleHealthRow(_ name: String) {
        if expandedHealthRow == name {
            expandedHealthRow = nil
        } else {
            expandedHealthRow = name
        }
    }
}

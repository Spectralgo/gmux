import Foundation
import Combine

/// The unified Gas Town dashboard panel — the default view when Gas Town is detected.
/// Shows 4 sections: Agent Roster, Attention, Bead Summary, Activity Feed.
/// Auto-refreshes via GasTownService.refreshTick.
@MainActor
final class TownDashboardPanel: Panel, ObservableObject {
    let id: UUID
    let panelType: PanelType = .townDashboard

    @Published private(set) var displayTitle: String

    var displayIcon: String? { "building.2" }

    @Published private(set) var loadState: TownDashboardLoadState = .idle

    /// Whether infrastructure agents (refinery, witness, deacon) are collapsed.
    @Published var infrastructureCollapsed: Bool = true

    /// Token incremented to trigger focus flash animation.
    @Published private(set) var focusFlashToken: Int = 0

    private(set) var workspaceId: UUID
    private let adapter: TownDashboardAdapter

    init(workspaceId: UUID, adapter: TownDashboardAdapter = TownDashboardAdapter()) {
        self.id = UUID()
        self.workspaceId = workspaceId
        self.adapter = adapter
        self.displayTitle = String(
            localized: "townDashboard.title",
            defaultValue: "Town Dashboard"
        )
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

    /// Load all dashboard data. Tries the socket adapter (direct Dolt query)
    /// first, then falls back to CLI subprocesses.
    ///
    /// - Parameter silent: When `true` (auto-refresh), skips `.loading` state
    ///   and only publishes if data changed.
    func refresh(silent: Bool = false) {
        if !silent {
            loadState = .loading
        }

        // Try socket adapter first (no subprocess, direct Dolt query)
        let socketAdapter = GasTownSocketAdapter.shared
        if let snapshot = TownDashboardAdapter.loadSnapshotFromSocket(socketAdapter) {
            let newState = TownDashboardLoadState.loaded(snapshot)
            if loadState != newState {
                loadState = newState
            }
            return
        }

        // Fall back to CLI subprocess
        let adapter = self.adapter
        DispatchQueue.global(qos: .userInitiated).async {
            let result = adapter.loadSnapshot()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let snapshot):
                    let newState = TownDashboardLoadState.loaded(snapshot)
                    if self.loadState != newState {
                        self.loadState = newState
                    }
                case .failure(let error):
                    let newState = TownDashboardLoadState.failed(error)
                    if self.loadState != newState {
                        self.loadState = newState
                    }
                }
            }
        }
    }
}

import Foundation
import SwiftUI

/// Panel displaying an RPG-style character sheet for an AI agent.
///
/// Shows health status, stats, skills, memories, and bead history.
/// Health updates silently every 8s via ``GasTownService/refreshTick``.
/// Bead history refreshes on demand only (expensive query).
@MainActor
final class AgentProfilePanel: Panel, ObservableObject {
    let id: UUID
    let panelType: PanelType = .agentProfile

    @Published private(set) var displayTitle: String
    @Published private(set) var loadState: AgentProfileLoadState = .idle
    @Published private(set) var focusFlashToken: Int = 0

    /// Action result toast (auto-dismisses after 4s).
    @Published var actionResult: GasTownActionResult?

    var displayIcon: String? {
        if let role = currentHealth?.role {
            return GasTownRoleIcon.sfSymbol(for: role)
        }
        return "person.crop.rectangle"
    }

    /// The agent address this profile displays (e.g. "gmux/polecats/fury").
    let agentAddress: String
    let workspaceId: UUID

    private let adapter: AgentProfileAdapter
    private var tickCounter: Int = 0

    /// Cached health entry for silent refresh comparison.
    private(set) var currentHealth: AgentHealthEntry?
    /// Cached bead history for stats/skills/CV computation.
    private(set) var beadHistory: [BeadSummary] = []
    /// Agent memories.
    private(set) var memories: [String] = []

    // Computed from beadHistory
    var stats: AgentStats { AgentStats.compute(from: beadHistory) }
    var skills: [AgentSkill] { AgentSkill.derive(from: beadHistory) }

    init(agentAddress: String, workspaceId: UUID, adapter: AgentProfileAdapter) {
        self.id = UUID()
        self.agentAddress = agentAddress
        self.workspaceId = workspaceId
        self.adapter = adapter
        // Extract short name from address (last path component)
        self.displayTitle = agentAddress.split(separator: "/").last.map(String.init) ?? agentAddress
    }

    // MARK: - Panel Protocol

    func focus() {}
    func unfocus() {}
    func close() {}

    func triggerFlash(reason: WorkspaceAttentionFlashReason) {
        _ = reason
        guard NotificationPaneFlashSettings.isEnabled() else { return }
        focusFlashToken += 1
    }

    // MARK: - Refresh

    /// Full or silent refresh.
    ///
    /// - Parameter silent: When `true`, skips the `.loading` state and only publishes
    ///   if values differ (prevents flicker on 8s health ticks).
    func refresh(silent: Bool = false) {
        if silent {
            // Silent: only refresh health (cheap).
            // Full bead refresh every 5th tick (40s).
            tickCounter += 1
            let includeBeads = tickCounter % 5 == 0

            let adapter = self.adapter
            let address = self.agentAddress

            Task {
                let newHealth = await adapter.loadHealthOnly(agentAddress: address)
                if let newHealth, self.currentHealth != newHealth {
                    self.currentHealth = newHealth
                    self.displayTitle = newHealth.name
                }
            }

            if includeBeads {
                refreshBeadHistory()
            }
        } else {
            // Full: set loading, fetch everything.
            loadState = .loading

            let adapter = self.adapter
            let address = self.agentAddress

            Task {
                let result = await adapter.loadProfile(agentAddress: address)
                switch result {
                case .success(let snapshot):
                    self.currentHealth = snapshot.health
                    self.beadHistory = snapshot.beadHistory
                    self.memories = snapshot.memories
                    if let name = snapshot.health?.name {
                        self.displayTitle = name
                    }
                    self.loadState = .loaded(snapshot)
                case .failure(let error):
                    let newState = AgentProfileLoadState.failed(error)
                    if self.loadState != newState {
                        self.loadState = newState
                    }
                }
            }
        }
    }

    /// Refresh only the bead history section.
    func refreshBeadHistory() {
        let adapter = self.adapter
        let address = self.agentAddress

        Task {
            let result = await adapter.loadProfile(agentAddress: address)
            if case .success(let snapshot) = result {
                if self.beadHistory != snapshot.beadHistory {
                    self.beadHistory = snapshot.beadHistory
                }
                if self.memories != snapshot.memories {
                    self.memories = snapshot.memories
                }
            }
        }
    }

    /// Add a memory via socket handler.
    func addMemory(_ text: String) {
        Task { [weak self] in
            let result = await GastownSocketHandlers.gastownRemember(params: ["text": text])

            await MainActor.run {
                guard let self else { return }
                switch result {
                case .ok:
                    self.showActionResult(.success(String(
                        localized: "agentProfile.action.remembered",
                        defaultValue: "Memory saved"
                    )))
                    self.refreshBeadHistory()
                case .err(_, let message):
                    self.showActionResult(.failure(message))
                }
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
}

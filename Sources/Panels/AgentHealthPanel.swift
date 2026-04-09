import Foundation
import Combine

/// A panel that displays a live agent health grid using the AgentHealthAdapter.
/// Auto-refreshes via GasTownService.refreshTick.
@MainActor
final class AgentHealthPanel: Panel, ObservableObject {
    let id: UUID
    let panelType: PanelType = .agentHealth

    @Published private(set) var displayTitle: String

    var displayIcon: String? { "person.3" }

    @Published private(set) var loadState: AgentHealthLoadState = .idle

    /// Token incremented to trigger focus flash animation.
    @Published private(set) var focusFlashToken: Int = 0

    private(set) var workspaceId: UUID
    private let adapter: AgentHealthAdapter

    init(workspaceId: UUID, adapter: AgentHealthAdapter = AgentHealthAdapter()) {
        self.id = UUID()
        self.workspaceId = workspaceId
        self.adapter = adapter
        self.displayTitle = String(
            localized: "agentHealth.title",
            defaultValue: "Agent Health"
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

    // MARK: - Data Loading

    /// Load agent health data from `gt status --json`. Runs CLI off-main
    /// to avoid blocking UI, then publishes the result on main.
    func refresh() {
        loadState = .loading

        let adapter = self.adapter
        DispatchQueue.global(qos: .userInitiated).async {
            let result = adapter.loadAgents()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let entries):
                    self.loadState = .loaded(entries)
                case .failure(let error):
                    self.loadState = .failed(error)
                }
            }
        }
    }
}

import Foundation
import Combine

/// A panel that displays Beads ready-work items using the BeadsAdapter.
/// Refresh is explicit — triggered by user action or programmatic request.
@MainActor
final class ReadyWorkPanel: Panel, ObservableObject {
    let id: UUID
    let panelType: PanelType = .readyWork

    @Published private(set) var displayTitle: String

    var displayIcon: String? { "tray.full" }

    @Published private(set) var loadState: BeadsLoadState<[BeadSummary]> = .idle

    /// Detail for a selected bead, if any.
    @Published private(set) var selectedDetail: BeadsLoadState<BeadDetail> = .idle
    @Published var selectedBeadId: String?

    /// Token incremented to trigger focus flash animation.
    @Published private(set) var focusFlashToken: Int = 0

    private(set) var workspaceId: UUID
    private let adapter: BeadsAdapter

    init(workspaceId: UUID, adapter: BeadsAdapter = BeadsAdapter()) {
        self.id = UUID()
        self.workspaceId = workspaceId
        self.adapter = adapter
        self.displayTitle = String(
            localized: "readyWork.title",
            defaultValue: "Ready Work"
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

    /// Load ready work items from the Beads CLI. Runs the CLI off-main
    /// to avoid blocking UI, then publishes the result on main.
    func refresh() {
        loadState = .loading
        selectedBeadId = nil
        selectedDetail = .idle

        let adapter = self.adapter
        DispatchQueue.global(qos: .userInitiated).async {
            let result = adapter.loadReadyWork()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let summaries):
                    self.loadState = .loaded(summaries)
                case .failure(let error):
                    self.loadState = .failed(error)
                }
            }
        }
    }

    /// Load detail for a specific bead. Used when a row is expanded.
    func loadDetail(for beadId: String) {
        selectedBeadId = beadId
        selectedDetail = .loading

        let adapter = self.adapter
        DispatchQueue.global(qos: .userInitiated).async {
            let result = adapter.loadBeadDetail(id: beadId)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.selectedBeadId == beadId else { return }
                switch result {
                case .success(let detail):
                    self.selectedDetail = .loaded(detail)
                case .failure(let error):
                    self.selectedDetail = .failed(error)
                }
            }
        }
    }

    func clearSelection() {
        selectedBeadId = nil
        selectedDetail = .idle
    }
}

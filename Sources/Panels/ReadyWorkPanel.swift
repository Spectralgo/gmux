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
    ///
    /// - Parameter silent: When `true` (used by auto-refresh), skips the
    ///   `.loading` transition and only publishes if the result differs from
    ///   the current state, preventing unnecessary SwiftUI re-renders.
    func refresh(silent: Bool = false) {
        if !silent {
            loadState = .loading
            selectedBeadId = nil
            selectedDetail = .idle
        }

        let adapter = self.adapter
        DispatchQueue.global(qos: .userInitiated).async {
            let result = adapter.loadReadyWork()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let summaries):
                    let newState: BeadsLoadState<[BeadSummary]> = .loaded(summaries)
                    if self.loadState != newState {
                        self.loadState = newState
                    }
                case .failure(let error):
                    let newState: BeadsLoadState<[BeadSummary]> = .failed(error)
                    if self.loadState != newState {
                        self.loadState = newState
                    }
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

    // MARK: - Actions

    /// Result message from the last action, cleared on next action.
    @Published private(set) var actionResult: ActionResult?

    enum ActionResult: Equatable {
        case success(String)
        case failure(String)
    }

    /// Sling a bead to a rig via `gt sling <beadId> <rig>`.
    func slingBead(_ beadId: String, toRig rig: String) {
        actionResult = nil
        DispatchQueue.global(qos: .userInitiated).async {
            Task {
                let result = await GastownCommandRunner.gt(["sling", beadId, rig])
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if result.succeeded {
                        self.actionResult = .success(String(
                            localized: "readyWork.action.slingSuccess",
                            defaultValue: "Slung \(beadId) to \(rig)"
                        ))
                        self.refresh()
                    } else {
                        self.actionResult = .failure(result.stderr.isEmpty ? result.stdout : result.stderr)
                    }
                }
            }
        }
    }
}

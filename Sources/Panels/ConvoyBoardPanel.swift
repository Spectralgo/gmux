import Foundation
import SwiftUI
import Combine

/// Load state for the Convoy Board Panel.
enum ConvoyBoardLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

/// Panel showing a board view of all active convoys with progress,
/// attention states, and tracked issue drill-down.
///
/// Uses ``ConvoyAdapter`` to fetch convoy data via the `gt` CLI.
/// Auto-refreshes every 4th tick (~32s) via `GasTownService.shared.$refreshTick`.
@MainActor
final class ConvoyBoardPanel: Panel, ObservableObject {
    let id: UUID
    let panelType: PanelType = .convoyBoard

    @Published private(set) var displayTitle: String = String(localized: "convoyBoard.title", defaultValue: "Convoys")
    @Published private(set) var loadState: ConvoyBoardLoadState = .idle
    @Published private(set) var focusFlashToken: Int = 0

    /// All active convoys (open).
    @Published private(set) var convoys: [ConvoySummary] = []
    /// Detail for the currently selected convoy.
    @Published private(set) var selectedDetail: ConvoyDetail?
    /// Molecule progress keyed by bead ID for tracked issues.
    @Published private(set) var moleculeProgress: [String: MoleculeProgress] = [:]
    /// Currently selected convoy ID.
    @Published var selectedConvoyId: String?
    /// Whether to show closed convoys.
    @Published var showClosed: Bool = false

    var displayIcon: String? { "shippingbox" }

    let workspaceId: UUID
    private let adapter: ConvoyAdapter
    private let beadsAdapter: BeadsAdapter

    /// Optional initial convoy ID to auto-select on first load.
    private var initialConvoyId: String?
    /// Optional initial filter (e.g., "ready", "in_progress") for future use.
    let initialFilter: String?

    init(workspaceId: UUID, adapter: ConvoyAdapter, beadsAdapter: BeadsAdapter? = nil, convoyId: String? = nil, filter: String? = nil) {
        self.id = UUID()
        self.workspaceId = workspaceId
        self.adapter = adapter
        self.beadsAdapter = beadsAdapter ?? BeadsAdapter()
        self.initialConvoyId = convoyId
        self.initialFilter = filter
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

    // MARK: - Computed

    /// Convoys that need operator attention (stranded or blocked).
    var attentionConvoys: [ConvoySummary] {
        convoys.filter { $0.needsAttention }
    }

    /// Convoys progressing normally.
    var normalConvoys: [ConvoySummary] {
        convoys.filter { !$0.needsAttention }
    }

    // MARK: - Actions

    func selectConvoy(_ id: String?) {
        selectedConvoyId = id
        if let id {
            loadDetail(convoyId: id)
        } else {
            selectedDetail = nil
        }
    }

    // MARK: - Refresh

    func refresh(silent: Bool = false) {
        if !silent {
            loadState = .loading
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.showClosed
                ? self.adapter.loadAllConvoys()
                : self.adapter.loadActiveConvoys()

            DispatchQueue.main.async {
                switch result {
                case .success(let summaries):
                    // Diff before publish to avoid unnecessary SwiftUI churn.
                    if self.convoys != summaries {
                        self.convoys = summaries
                    }
                    if self.loadState != .loaded {
                        self.loadState = .loaded
                    }

                    // Auto-select initial convoy on first load.
                    if let initial = self.initialConvoyId {
                        self.initialConvoyId = nil
                        self.selectConvoy(initial)
                    }

                case .failure(let error):
                    if !silent {
                        self.loadState = .failed(self.errorMessage(error))
                    }
                }
            }
        }
    }

    // MARK: - Detail Loading

    private func loadDetail(convoyId: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.adapter.loadConvoyDetail(id: convoyId)

            DispatchQueue.main.async {
                switch result {
                case .success(let detail):
                    if self.selectedDetail != detail {
                        self.selectedDetail = detail
                    }
                    self.refreshMoleculeProgress(for: detail.trackedIssues)
                case .failure:
                    self.selectedDetail = nil
                }
            }
        }
    }

    // MARK: - Molecule Progress

    /// Refresh molecule progress for active (non-closed) tracked issues.
    func refreshMoleculeProgress(for issues: [ConvoyTrackedIssue]) {
        let activeIssueIds = issues
            .filter { $0.status != "closed" }
            .map(\.id)
        guard !activeIssueIds.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var newProgress: [String: MoleculeProgress] = [:]
            for beadId in activeIssueIds {
                if case .success(let progress) = self.beadsAdapter.loadMoleculeProgress(beadId: beadId) {
                    newProgress[beadId] = progress
                }
            }

            DispatchQueue.main.async {
                if self.moleculeProgress != newProgress {
                    self.moleculeProgress = newProgress
                }
            }
        }
    }

    // MARK: - Helpers

    private func errorMessage(_ error: ConvoyAdapterError) -> String {
        switch error {
        case .gtCLINotFound:
            return String(localized: "convoyBoard.error.noCLI", defaultValue: "Gas Town CLI not found")
        case .cliFailure(_, _, let stderr):
            return stderr.isEmpty
                ? String(localized: "convoyBoard.error.cliFailed", defaultValue: "Failed to load convoys")
                : stderr
        case .parseFailure(_, let detail):
            return detail
        case .convoyNotFound(let id):
            return String(localized: "convoyBoard.error.notFound", defaultValue: "Convoy '\(id)' not found")
        }
    }
}

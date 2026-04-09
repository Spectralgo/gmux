import Foundation
import Combine

/// A panel that displays detailed bead information from the Beads tracking system.
/// Fetches data via the BeadsAdapter and auto-refreshes on request.
@MainActor
final class BeadInspectorPanel: Panel, ObservableObject {
    let id: UUID
    let panelType: PanelType = .beadInspector

    /// The bead ID being inspected.
    let beadId: String

    /// The workspace this panel belongs to.
    private(set) var workspaceId: UUID

    /// Current bead detail data, nil while loading or if fetch failed.
    @Published private(set) var beadDetail: BeadDetail?

    /// Whether the adapter is currently loading.
    @Published private(set) var isLoading: Bool = true

    /// Error message from the last fetch, if any.
    @Published private(set) var errorMessage: String?

    /// Title shown in the tab bar.
    @Published private(set) var displayTitle: String = ""

    /// SF Symbol icon for the tab bar.
    var displayIcon: String? { "doc.text.magnifyingglass" }

    /// Token incremented to trigger focus flash animation.
    @Published private(set) var focusFlashToken: Int = 0

    private let adapter: BeadsAdapter
    private var isClosed = false

    // MARK: - Init

    init(workspaceId: UUID, beadId: String, townRootPath: String? = nil) {
        self.id = UUID()
        self.workspaceId = workspaceId
        self.beadId = beadId
        self.displayTitle = beadId
        self.adapter = BeadsAdapter(townRootPath: townRootPath)

        Task { @MainActor [weak self] in
            await self?.refresh()
        }
    }

    // MARK: - Panel protocol

    func focus() {
        // Bead inspector is read-only; no first responder to manage.
    }

    func unfocus() {
        // No-op for read-only panel.
    }

    func close() {
        isClosed = true
    }

    func triggerFlash(reason: WorkspaceAttentionFlashReason) {
        _ = reason
        guard NotificationPaneFlashSettings.isEnabled() else { return }
        focusFlashToken += 1
    }

    // MARK: - Actions

    /// Result message from the last action.
    @Published private(set) var actionResult: ActionResult?

    enum ActionResult: Equatable {
        case success(String)
        case failure(String)
    }

    /// Close the bead via `bd close <beadId>`.
    func closeBead() {
        actionResult = nil
        let id = beadId
        Task { @MainActor [weak self] in
            let result = await GastownCommandRunner.bd(["close", id])
            guard let self, !self.isClosed else { return }
            if result.succeeded {
                self.actionResult = .success(String(
                    localized: "beadInspector.action.closeSuccess",
                    defaultValue: "Bead \(id) closed"
                ))
                await self.refresh()
            } else {
                self.actionResult = .failure(result.stderr.isEmpty ? result.stdout : result.stderr)
            }
        }
    }

    /// Assign the bead via `bd update <beadId> --assignee <assignee>`.
    func assignBead(to assignee: String) {
        actionResult = nil
        let id = beadId
        Task { @MainActor [weak self] in
            let result = await GastownCommandRunner.bd(["update", id, "--assignee", assignee])
            guard let self, !self.isClosed else { return }
            if result.succeeded {
                self.actionResult = .success(String(
                    localized: "beadInspector.action.assignSuccess",
                    defaultValue: "Assigned \(id) to \(assignee)"
                ))
                await self.refresh()
            } else {
                self.actionResult = .failure(result.stderr.isEmpty ? result.stdout : result.stderr)
            }
        }
    }

    // MARK: - Data

    func refresh() async {
        guard !isClosed else { return }
        isLoading = true
        errorMessage = nil

        if let detail = await adapter.fetchBeadDetail(beadId: beadId) {
            beadDetail = detail
            displayTitle = detail.id
        } else {
            errorMessage = adapter.lastError
                ?? String(localized: "beadInspector.error.unknown", defaultValue: "Failed to load bead")
        }

        isLoading = false
    }
}

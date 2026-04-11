import Foundation
import Combine

/// Engine Room panel — diagnostics dashboard for Gas Town health.
///
/// Phase 1: traffic lights (system / agents / storage), expandable detail
/// sections, 30-second polling via ``DiagnosticsStore``.
///
/// Follows the ``TownDashboardPanel`` pattern: `@ObservedObject` in the
/// view, `@Published` on the panel, focus flash via `focusFlashToken`.
@MainActor
final class DiagnosticsPanel: Panel, ObservableObject {
    let id: UUID
    let panelType: PanelType = .diagnostics

    @Published private(set) var displayTitle: String

    var displayIcon: String? { "stethoscope" }

    /// The diagnostics data store.
    let store: DiagnosticsStore

    /// Token incremented to trigger focus flash animation.
    @Published private(set) var focusFlashToken: Int = 0

    /// Workspace that owns this panel.
    let workspaceId: UUID

    init(workspaceId: UUID, store: DiagnosticsStore? = nil) {
        self.id = UUID()
        self.workspaceId = workspaceId
        self.store = store ?? DiagnosticsStore()
        self.displayTitle = String(
            localized: "diagnostics.title",
            defaultValue: "Engine Room"
        )
    }

    // MARK: - Panel protocol

    func focus() {}
    func unfocus() {}
    func close() {
        store.stopPolling()
    }

    func triggerFlash(reason: WorkspaceAttentionFlashReason) {
        _ = reason
        guard NotificationPaneFlashSettings.isEnabled() else { return }
        focusFlashToken += 1
    }
}

import Foundation

/// Stub: Diff panel for review workspace (TASK-026)
/// Full implementation on polecat/scavenger-mnnkvb1b branch
@MainActor
final class DiffPanel: Panel, ObservableObject {
    let id: UUID
    let panelType: PanelType = .diff
    let workspaceId: UUID
    let repositoryPath: String?
    let baseRevision: String?

    @Published private(set) var displayTitle: String = String(
        localized: "panel.diff.title",
        defaultValue: "Diff Review"
    )
    var displayIcon: String? { "arrow.left.arrow.right" }
    var isDirty: Bool { false }

    init(workspaceId: UUID, repositoryPath: String? = nil, baseRevision: String? = nil) {
        self.id = UUID()
        self.workspaceId = workspaceId
        self.repositoryPath = repositoryPath
        self.baseRevision = baseRevision
    }

    func close() {}
    func focus() {}
    func unfocus() {}
    func triggerFlash(reason: WorkspaceAttentionFlashReason) {}
}

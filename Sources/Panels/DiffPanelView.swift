import SwiftUI

/// Stub: Diff panel view (TASK-026)
/// Full implementation on polecat/scavenger-mnnkvb1b branch
struct DiffPanelView: View {
    let panel: DiffPanel
    let isFocused: Bool
    let isVisibleInUI: Bool
    let portalPriority: Int
    let onRequestPanelFocus: () -> Void

    var body: some View {
        Text(String(
            localized: "panel.diff.placeholder",
            defaultValue: "Diff Review (coming soon)"
        ))
            .foregroundColor(.secondary)
    }
}

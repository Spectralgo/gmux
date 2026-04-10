import SwiftUI

/// Config section showing rig identity and reference information.
struct RigConfigSection: View {
    let rig: Rig
    let workspaceId: UUID

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: GasTownSpacing.gridGap) {
            Text(String(localized: "rigPanel.config.sectionTitle", defaultValue: "Config"))
                .font(GasTownTypography.sectionHeader)

            configRow(
                label: String(localized: "rigPanel.config.gitUrl", defaultValue: "Git URL:"),
                value: displayGitURL(rig.config.git_url)
            )
            configRow(
                label: String(localized: "rigPanel.config.defaultBranch", defaultValue: "Default branch:"),
                value: rig.config.default_branch
            )
            configRow(
                label: String(localized: "rigPanel.config.beadPrefix", defaultValue: "Bead prefix:"),
                value: rig.config.beads.prefix
            )

            HStack {
                Spacer()
                Button(String(localized: "rigPanel.action.viewConfig", defaultValue: "View Config")) {
                    let configPath = rig.path.appendingPathComponent("config.json").path
                    NotificationCenter.default.post(
                        name: Notification.Name("com.cmux.openFile"),
                        object: nil,
                        userInfo: [
                            "path": configPath,
                            "workspaceId": workspaceId,
                        ]
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(GasTownSpacing.cardPadding)
        .background(GasTownColors.sectionBackground(for: colorScheme))
        .cornerRadius(8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(
            localized: "rigPanel.config.a11y",
            defaultValue: "Config section"
        ))
    }

    // MARK: - Config Row

    @ViewBuilder
    private func configRow(label: String, value: String) -> some View {
        HStack(spacing: GasTownSpacing.gridGap) {
            Text(label)
                .font(GasTownTypography.label)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .trailing)
            Text(value)
                .font(GasTownTypography.data)
                .lineLimit(1)
            Spacer()
        }
    }

    private func displayGitURL(_ url: String) -> String {
        var display = url
        if display.hasPrefix("https://") { display = String(display.dropFirst(8)) }
        if display.hasPrefix("http://") { display = String(display.dropFirst(7)) }
        if display.hasSuffix(".git") { display = String(display.dropLast(4)) }
        return display
    }
}

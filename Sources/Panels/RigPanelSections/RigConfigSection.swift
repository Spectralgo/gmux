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

            // Operational config fields
            if let status = rig.config.status {
                HStack(spacing: GasTownSpacing.gridGap) {
                    Text(String(localized: "rigPanel.config.status", defaultValue: "Status:"))
                        .font(GasTownTypography.label)
                        .foregroundColor(.secondary)
                        .frame(width: 120, alignment: .trailing)
                    rigStatusBadge(status)
                    Spacer()
                }
            }

            if let maxPolecats = rig.config.max_polecats {
                configRow(
                    label: String(localized: "rigPanel.config.maxPolecats", defaultValue: "Max polecats:"),
                    value: "\(maxPolecats)"
                )
            }

            if let autoRestart = rig.config.auto_restart {
                configRow(
                    label: String(localized: "rigPanel.config.autoRestart", defaultValue: "Auto-restart:"),
                    value: autoRestart
                        ? String(localized: "rigPanel.config.on", defaultValue: "on")
                        : String(localized: "rigPanel.config.off", defaultValue: "off")
                )
            }

            if let dnd = rig.config.dnd, dnd {
                HStack(spacing: GasTownSpacing.gridGap) {
                    Text(String(localized: "rigPanel.config.dnd", defaultValue: "DND:"))
                        .font(GasTownTypography.label)
                        .foregroundColor(.secondary)
                        .frame(width: 120, alignment: .trailing)
                    Image(systemName: "moon.fill")
                        .font(.caption)
                        .foregroundColor(GasTownColors.attention)
                    Text(String(localized: "rigPanel.config.dndActive", defaultValue: "do not disturb"))
                        .font(GasTownTypography.data)
                        .foregroundColor(GasTownColors.attention)
                    Spacer()
                }
            }

            if let namepool = rig.config.namepool {
                configRow(
                    label: String(localized: "rigPanel.config.namepool", defaultValue: "Name pool:"),
                    value: namepool
                )
            }

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

    @ViewBuilder
    private func rigStatusBadge(_ status: String) -> some View {
        let color: Color = {
            switch status.lowercased() {
            case "operational": return GasTownColors.active
            case "parked": return GasTownColors.idle
            case "docked": return GasTownColors.attention
            default: return GasTownColors.idle
            }
        }()

        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: GasTownStatusDot.size, height: GasTownStatusDot.size)
            Text(status)
                .font(GasTownTypography.data)
                .foregroundColor(color)
        }
        .accessibilityLabel(String(
            localized: "rigPanel.config.status.a11y",
            defaultValue: "Rig status: \(status)"
        ))
    }

    private func displayGitURL(_ url: String) -> String {
        var display = url
        if display.hasPrefix("https://") { display = String(display.dropFirst(8)) }
        if display.hasPrefix("http://") { display = String(display.dropFirst(7)) }
        if display.hasSuffix(".git") { display = String(display.dropLast(4)) }
        return display
    }
}

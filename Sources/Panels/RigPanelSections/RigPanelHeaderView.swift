import SwiftUI

/// Header bar showing rig identity, last commit, build status, and action buttons.
struct RigPanelHeaderView: View {
    let snapshot: RigPanelSnapshot
    let panel: RigPanel

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: GasTownSpacing.gridGap) {
            // Row 1: Rig icon + name, rig label
            HStack {
                Image(systemName: "folder.badge.gearshape")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text(snapshot.rig.name)
                    .font(.title2.bold())
                Spacer()
                Text(String(
                    localized: "rigPanel.header.rigLabel",
                    defaultValue: "rig: \(snapshot.rig.id)"
                ))
                .font(GasTownTypography.caption)
                .foregroundColor(.secondary)
            }

            // Row 2: Git URL, branch, build status
            HStack(spacing: GasTownSpacing.gridGap) {
                Text(displayGitURL(snapshot.rig.config.git_url))
                    .font(GasTownTypography.data)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 4) {
                    Text(String(
                        localized: "rigPanel.header.branch",
                        defaultValue: "branch:"
                    ))
                    .font(GasTownTypography.caption)
                    .foregroundColor(.secondary)
                    Text(snapshot.rig.config.default_branch)
                        .font(GasTownTypography.data)
                }

                HStack(spacing: 4) {
                    buildStatusDot(snapshot.healthIndicators.build)
                    Text(buildStatusLabel(snapshot.healthIndicators.build))
                        .font(GasTownTypography.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Row 3: Action buttons
            HStack(spacing: GasTownSpacing.gridGap) {
                Button(String(localized: "rigPanel.action.openWorkspace", defaultValue: "Open Workspace")) {
                    NotificationCenter.default.post(
                        name: .createRigWorkspace,
                        object: nil,
                        userInfo: ["rigId": snapshot.rig.id]
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(String(localized: "rigPanel.action.runDoctor", defaultValue: "Run Doctor")) {
                    panel.refresh()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()
            }
        }
        .padding(GasTownSpacing.cardPadding)
        .background(GasTownColors.sectionBackground(for: colorScheme))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(
            localized: "rigPanel.header.a11y",
            defaultValue: "Rig header"
        ))
    }

    // MARK: - Helpers

    private func displayGitURL(_ url: String) -> String {
        var display = url
        if display.hasPrefix("https://") { display = String(display.dropFirst(8)) }
        if display.hasPrefix("http://") { display = String(display.dropFirst(7)) }
        if display.hasSuffix(".git") { display = String(display.dropLast(4)) }
        return display
    }

    @ViewBuilder
    private func buildStatusDot(_ signal: HealthSignal) -> some View {
        Circle()
            .fill(colorForSignal(signal))
            .frame(width: GasTownStatusDot.size, height: GasTownStatusDot.size)
            .accessibilityLabel(String(
                localized: "rigPanel.header.buildStatus.a11y",
                defaultValue: "Build status"
            ))
            .accessibilityValue(accessibilityValueForSignal(signal))
    }

    private func buildStatusLabel(_ signal: HealthSignal) -> String {
        switch signal {
        case .green: return String(localized: "rigPanel.header.buildPassing", defaultValue: "passing")
        case .amber: return String(localized: "rigPanel.header.buildRunning", defaultValue: "running")
        case .red: return String(localized: "rigPanel.header.buildFailing", defaultValue: "failing")
        case .unknown: return String(localized: "rigPanel.header.buildUnknown", defaultValue: "unknown")
        }
    }

    private func colorForSignal(_ signal: HealthSignal) -> Color {
        switch signal {
        case .green: return GasTownColors.active
        case .amber: return GasTownColors.attention
        case .red: return GasTownColors.error
        case .unknown: return GasTownColors.idle
        }
    }

    private func accessibilityValueForSignal(_ signal: HealthSignal) -> String {
        switch signal {
        case .green: return String(localized: "rigPanel.a11y.passing", defaultValue: "Passing")
        case .amber: return String(localized: "rigPanel.a11y.needsAttention", defaultValue: "Needs attention")
        case .red: return String(localized: "rigPanel.a11y.failing", defaultValue: "Failing")
        case .unknown: return String(localized: "rigPanel.a11y.unknown", defaultValue: "Unknown")
        }
    }
}

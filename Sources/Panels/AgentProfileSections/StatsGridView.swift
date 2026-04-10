import SwiftUI

/// 2×4 grid of stat cards showing agent statistics.
struct StatsGridView: View {
    let stats: AgentStats

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: GasTownSpacing.gridGap) {
            Text(String(localized: "agentProfile.stats.title", defaultValue: "Stats"))
                .font(GasTownTypography.sectionHeader)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: GasTownSpacing.gridGap),
                    GridItem(.flexible(), spacing: GasTownSpacing.gridGap),
                    GridItem(.flexible(), spacing: GasTownSpacing.gridGap),
                    GridItem(.flexible(), spacing: GasTownSpacing.gridGap),
                ],
                spacing: GasTownSpacing.gridGap
            ) {
                statCard(
                    label: String(localized: "agentProfile.stats.completed", defaultValue: "Completed"),
                    value: "\(stats.tasksCompleted)"
                )
                statCard(
                    label: String(localized: "agentProfile.stats.successRate", defaultValue: "Success"),
                    value: "\(Int(stats.successRate * 100))%"
                )
                statCard(
                    label: String(localized: "agentProfile.stats.total", defaultValue: "Total"),
                    value: "\(stats.totalBeads)"
                )
                statCard(
                    label: String(localized: "agentProfile.stats.open", defaultValue: "Open"),
                    value: "\(stats.openBeads)"
                )
                statCard(
                    label: String(localized: "agentProfile.stats.blocked", defaultValue: "Blocked"),
                    value: "\(stats.blockedBeads)"
                )
                statCard(
                    label: String(localized: "agentProfile.stats.avgPriority", defaultValue: "Avg Priority"),
                    value: stats.avgPriority > 0 ? String(format: "P%.0f", stats.avgPriority) : "-"
                )
                statCard(
                    label: String(localized: "agentProfile.stats.labels", defaultValue: "Labels"),
                    value: "\(stats.labelCount)"
                )
                statCard(
                    label: String(localized: "agentProfile.stats.deps", defaultValue: "Dependencies"),
                    value: "\(stats.dependencyTotal)"
                )
            }
        }
        .padding(GasTownSpacing.cardPadding)
        .background(GasTownColors.sectionBackground(for: colorScheme))
        .cornerRadius(8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(
            localized: "agentProfile.stats.section.a11y",
            defaultValue: "Statistics section"
        ))
    }

    @ViewBuilder
    private func statCard(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(GasTownTypography.data)
                .foregroundColor(.primary)
            Text(label)
                .font(GasTownTypography.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

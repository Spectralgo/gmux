import SwiftUI

/// Detail view for a selected convoy showing tracked issues.
///
/// Displayed in the right side of the board's master-detail split.
/// Shows convoy header with progress, then a list of tracked issues
/// grouped by status.
struct ConvoyDetailSection: View {
    let detail: ConvoyDetail

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GasTownSpacing.sectionGap) {
                // Header
                detailHeader

                Divider()

                // Tracked issues
                if detail.trackedIssues.isEmpty {
                    emptyIssuesView
                } else {
                    issuesList
                }
            }
            .padding(GasTownSpacing.cardPadding)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(
            localized: "convoyDetail.a11y",
            defaultValue: "Convoy detail: \(detail.title)"
        ))
    }

    // MARK: - Header

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: GasTownSpacing.gridGap) {
            HStack {
                Text(detail.title)
                    .font(GasTownTypography.sectionHeader)
                    .fontWeight(.semibold)

                Spacer()

                attentionBadge
            }

            if let description = detail.description, !description.isEmpty {
                Text(description)
                    .font(GasTownTypography.label)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            // Progress summary
            HStack(spacing: GasTownSpacing.gridGap) {
                progressBar

                Text(String(
                    localized: "convoyDetail.progress",
                    defaultValue: "\(detail.completedIssues)/\(detail.totalIssues) issues"
                ))
                .font(GasTownTypography.data)
                .foregroundColor(.secondary)

                Text("(\(Int(detail.progress * 100))%)")
                    .font(GasTownTypography.data)
                    .foregroundColor(.secondary)
            }

            // Rig tags
            if !detail.rigIds.isEmpty {
                HStack(spacing: 4) {
                    Text(String(localized: "convoyDetail.rigs", defaultValue: "Rigs:"))
                        .font(GasTownTypography.caption)
                        .foregroundColor(.secondary)

                    ForEach(detail.rigIds, id: \.self) { rigId in
                        Text(rigId)
                            .font(GasTownTypography.badge)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(3)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var attentionBadge: some View {
        switch detail.attention {
        case .normal:
            EmptyView()
        case .stranded:
            Text(String(localized: "convoyDetail.stranded", defaultValue: "stranded"))
                .font(GasTownTypography.badge)
                .foregroundColor(GasTownColors.attention)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(GasTownColors.attention.opacity(0.15))
                .cornerRadius(3)
        case .blocked:
            Text(String(localized: "convoyDetail.blocked", defaultValue: "blocked"))
                .font(GasTownTypography.badge)
                .foregroundColor(GasTownColors.error)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(GasTownColors.error.opacity(0.15))
                .cornerRadius(3)
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.15))
                RoundedRectangle(cornerRadius: 3)
                    .fill(detail.progress >= 1.0 ? GasTownColors.active : Color.accentColor)
                    .frame(width: geo.size.width * min(max(detail.progress, 0), 1))
            }
        }
        .frame(height: 8)
        .frame(maxWidth: 200)
    }

    // MARK: - Issues List

    private var issuesList: some View {
        VStack(alignment: .leading, spacing: GasTownSpacing.gridGap) {
            Text(String(localized: "convoyDetail.issues.title", defaultValue: "Tracked Issues"))
                .font(GasTownTypography.sectionHeader)

            // Open issues first, then closed
            let openIssues = detail.trackedIssues.filter { $0.status != "closed" }
            let closedIssues = detail.trackedIssues.filter { $0.status == "closed" }

            if !openIssues.isEmpty {
                ForEach(openIssues) { issue in
                    issueRow(issue)
                }
            }

            if !closedIssues.isEmpty {
                Text(String(localized: "convoyDetail.issues.closed", defaultValue: "Closed"))
                    .font(GasTownTypography.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)

                ForEach(closedIssues) { issue in
                    issueRow(issue)
                }
            }
        }
    }

    private func issueRow(_ issue: ConvoyTrackedIssue) -> some View {
        HStack(spacing: GasTownSpacing.gridGap) {
            // Status indicator
            issueStatusIcon(issue.status)

            VStack(alignment: .leading, spacing: 2) {
                Text(issue.title)
                    .font(GasTownTypography.label)
                    .lineLimit(1)
                    .foregroundColor(issue.status == "closed" ? .secondary : .primary)

                HStack(spacing: 6) {
                    Text(issue.id)
                        .font(GasTownTypography.data)
                        .foregroundColor(.secondary)

                    if let assignee = issue.assignee, !assignee.isEmpty {
                        AgentNameLink(
                            name: shortAgentName(assignee),
                            agentAddress: assignee
                        )
                    }
                }
            }

            Spacer()

            if issue.priority > 0 {
                Text("P\(issue.priority)")
                    .font(GasTownTypography.badge)
                    .foregroundColor(priorityColor(issue.priority))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, GasTownSpacing.gridGap)
        .background(GasTownColors.sectionBackground(for: colorScheme))
        .cornerRadius(6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(
            localized: "convoyDetail.issue.a11y",
            defaultValue: "\(issue.title), status: \(issue.status)"
        ))
    }

    // MARK: - Empty State

    private var emptyIssuesView: some View {
        VStack(spacing: GasTownSpacing.gridGap) {
            Image(systemName: "tray")
                .font(.system(size: 24))
                .foregroundColor(.secondary.opacity(0.5))
            Text(String(localized: "convoyDetail.noIssues", defaultValue: "No tracked issues"))
                .font(GasTownTypography.label)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, GasTownSpacing.sectionGap)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func issueStatusIcon(_ status: String) -> some View {
        switch status {
        case "closed":
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(GasTownColors.active)
        case "in_progress", "hooked":
            Image(systemName: "circle.dotted")
                .font(.system(size: 14))
                .foregroundColor(Color.accentColor)
        case "blocked":
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(GasTownColors.error)
        default:
            Image(systemName: "circle")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
    }

    private func priorityColor(_ priority: Int) -> Color {
        switch priority {
        case 1: return GasTownColors.error
        case 2: return GasTownColors.attention
        default: return .secondary
        }
    }

    private func shortAgentName(_ address: String) -> String {
        // "gmux/polecats/rust" → "rust"
        address.split(separator: "/").last.map(String.init) ?? address
    }
}

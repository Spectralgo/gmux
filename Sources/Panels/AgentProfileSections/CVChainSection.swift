import SwiftUI

/// Section displaying bead history as a reverse-chronological CV chain.
struct CVChainSection: View {
    let beadHistory: [BeadSummary]
    let workspaceId: UUID

    @Environment(\.colorScheme) private var colorScheme
    @State private var showAll = false

    private let pageSize = 20

    var body: some View {
        VStack(alignment: .leading, spacing: GasTownSpacing.gridGap) {
            HStack {
                Text(String(localized: "agentProfile.cv.title", defaultValue: "Work History"))
                    .font(GasTownTypography.sectionHeader)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(String(
                    localized: "agentProfile.cv.count",
                    defaultValue: "\(beadHistory.count) beads"
                ))
                .font(GasTownTypography.caption)
                .foregroundColor(.secondary)
            }

            if beadHistory.isEmpty {
                Text(String(localized: "agentProfile.cv.empty", defaultValue: "No work history"))
                    .font(GasTownTypography.caption)
                    .foregroundColor(.secondary)
            } else {
                let displayed = showAll ? beadHistory : Array(beadHistory.prefix(pageSize))
                ForEach(displayed) { bead in
                    cvEntryRow(bead)
                }

                if beadHistory.count > pageSize && !showAll {
                    Button {
                        withAnimation(GasTownAnimation.newItem) {
                            showAll = true
                        }
                    } label: {
                        Text(String(
                            localized: "agentProfile.cv.viewAll",
                            defaultValue: "View full CV (\(beadHistory.count) entries)"
                        ))
                        .font(GasTownTypography.caption)
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(GasTownSpacing.cardPadding)
        .background(GasTownColors.sectionBackground(for: colorScheme))
        .cornerRadius(8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(
            localized: "agentProfile.cv.section.a11y",
            defaultValue: "Work history section"
        ))
    }

    @ViewBuilder
    private func cvEntryRow(_ bead: BeadSummary) -> some View {
        Button {
            NotificationCenter.default.post(
                name: .openBeadInspector,
                object: nil,
                userInfo: ["beadId": bead.id, "workspaceId": workspaceId]
            )
        } label: {
            HStack(spacing: GasTownSpacing.gridGap) {
                // Status icon
                Image(systemName: statusIcon(for: bead.status))
                    .font(.caption)
                    .foregroundColor(statusColor(for: bead.status))
                    .frame(width: 14)

                // Bead ID
                Text(bead.id)
                    .font(GasTownTypography.data)
                    .foregroundColor(.secondary)

                // Title
                Text(bead.title)
                    .font(GasTownTypography.label)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                // Priority
                if bead.priority > 0 {
                    Text("P\(bead.priority)")
                        .font(GasTownTypography.badge)
                        .foregroundColor(priorityColor(bead.priority))
                }

                // Type badge
                Text(bead.issueType)
                    .font(GasTownTypography.badge)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(
            localized: "agentProfile.cv.entry.a11y",
            defaultValue: "Bead \(bead.id), \(bead.title), \(bead.status)"
        ))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Helpers

    private func statusIcon(for status: String) -> String {
        switch status {
        case "closed": return "checkmark.circle"
        case "in_progress", "hooked": return "circle.dotted.circle"
        case "blocked": return "exclamationmark.circle"
        case "deferred": return "clock"
        case "open": return "circle"
        case "pinned": return "pin.circle"
        default: return "circle"
        }
    }

    private func statusColor(for status: String) -> Color {
        switch status {
        case "closed": return GasTownColors.active
        case "in_progress", "hooked": return .blue
        case "blocked": return GasTownColors.error
        case "deferred": return GasTownColors.attention
        case "open": return GasTownColors.idle
        case "pinned": return .purple
        default: return GasTownColors.idle
        }
    }

    private func priorityColor(_ priority: Int) -> Color {
        switch priority {
        case 1: return GasTownColors.error
        case 2: return GasTownColors.attention
        default: return .secondary
        }
    }
}

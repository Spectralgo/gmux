import SwiftUI

/// Full-width card displaying the agent's current hook bead.
///
/// Shows bead title, ID, and status badge. Tapping opens the bead inspector.
/// When no work is hooked, displays an idle "No work assigned" state.
struct HookBeadCardView: View {
    let health: AgentHealthEntry?
    let beadHistory: [BeadSummary]
    let workspaceId: UUID

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let hookBeadId = health?.currentTask {
                activeHookCard(beadId: hookBeadId)
            } else {
                idleHookCard
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(
            localized: "agentProfile.hookBead.a11y",
            defaultValue: "Hook bead card"
        ))
    }

    // MARK: - Active Hook

    @ViewBuilder
    private func activeHookCard(beadId: String) -> some View {
        let matchedBead = beadHistory.first { $0.id == beadId }
        let title = matchedBead?.title ?? beadId
        let status = matchedBead?.status ?? "hooked"

        Button {
            NotificationCenter.default.post(
                name: .openBeadInspector,
                object: nil,
                userInfo: ["beadId": beadId, "workspaceId": workspaceId]
            )
        } label: {
            VStack(alignment: .leading, spacing: GasTownSpacing.gridGap) {
                // Title row
                Text(title)
                    .font(GasTownTypography.sectionHeader)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                // ID + status badge row
                HStack(spacing: GasTownSpacing.gridGap) {
                    Text(beadId)
                        .font(GasTownTypography.data)
                        .foregroundColor(.secondary)

                    statusBadge(status)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(GasTownSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GasTownColors.sectionBackground(for: colorScheme))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(
            localized: "agentProfile.hookBead.hint.a11y",
            defaultValue: "Opens bead inspector"
        ))
    }

    // MARK: - Idle Hook

    private var idleHookCard: some View {
        HStack(spacing: GasTownSpacing.gridGap) {
            Image(systemName: "tray")
                .font(.caption)
                .foregroundColor(GasTownColors.idle)

            Text(String(localized: "agentProfile.hookBead.idle", defaultValue: "No work assigned"))
                .font(GasTownTypography.label)
                .foregroundColor(GasTownColors.idle)

            Spacer()
        }
        .padding(GasTownSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GasTownColors.sectionBackground(for: colorScheme))
        .cornerRadius(8)
    }

    // MARK: - Status Badge

    private func statusBadge(_ status: String) -> some View {
        Text(status)
            .font(GasTownTypography.badge)
            .foregroundColor(statusBadgeColor(status))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusBadgeColor(status).opacity(0.15))
            .cornerRadius(4)
    }

    private func statusBadgeColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "hooked", "in_progress":
            return GasTownColors.active
        case "open", "pinned":
            return .secondary
        case "blocked":
            return GasTownColors.attention
        case "closed":
            return GasTownColors.idle
        default:
            return .secondary
        }
    }
}

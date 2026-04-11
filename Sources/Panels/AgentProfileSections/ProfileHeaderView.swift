import SwiftUI

/// Header section showing agent name, role, status, context bar, and current task.
struct ProfileHeaderView: View {
    let health: AgentHealthEntry?
    let agentAddress: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: GasTownSpacing.gridGap) {
            // Row 1: Role icon + Name + Status dot
            HStack(spacing: GasTownSpacing.gridGap) {
                // Role icon
                Image(systemName: roleIcon)
                    .font(.system(size: 20))
                    .foregroundColor(roleColor)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)

                // Agent name
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)

                    HStack(spacing: 6) {
                        // Role badge
                        if let role = health?.role {
                            Text(role.capitalized)
                                .font(GasTownTypography.badge)
                                .foregroundColor(roleColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(roleColor.opacity(0.15))
                                .cornerRadius(4)
                        }

                        // Rig badge
                        if let rig = health?.rig {
                            Text(rig)
                                .font(GasTownTypography.badge)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }

                Spacer()

                // Status dot
                statusDotView
            }

            // Row 2: Context bar
            if let percent = health?.contextPercent {
                HStack(spacing: GasTownSpacing.gridGap) {
                    Text(String(localized: "agentProfile.context", defaultValue: "Context"))
                        .font(GasTownTypography.caption)
                        .foregroundColor(.secondary)

                    ContextBarView(percent: percent, maxWidth: .infinity)

                    Text(String(
                        localized: "agentProfile.contextPercent",
                        defaultValue: "\(Int(percent * 100))%"
                    ))
                    .font(GasTownTypography.data)
                    .foregroundColor(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(
                    localized: "agentProfile.contextBar.a11y",
                    defaultValue: "Context usage"
                ))
                .accessibilityValue(String(
                    localized: "agentProfile.contextBarValue.a11y",
                    defaultValue: "\(Int(percent * 100)) percent"
                ))
            }

            // Row 3: Current task
            if let task = health?.currentTask {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                        .foregroundColor(GasTownColors.active)
                    Text(task)
                        .font(GasTownTypography.data)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                }
            }

            // Row 4: Session info
            if let elapsed = health?.elapsed {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(
                        localized: "agentProfile.sessionElapsed",
                        defaultValue: "Session: \(elapsed)"
                    ))
                    .font(GasTownTypography.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding(GasTownSpacing.cardPadding)
        .background(GasTownColors.sectionBackground(for: colorScheme))
        .cornerRadius(8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(
            localized: "agentProfile.header.a11y",
            defaultValue: "Agent profile header"
        ))
    }

    // MARK: - Computed Properties

    private var displayName: String {
        health?.name ?? agentAddress.split(separator: "/").last.map(String.init) ?? agentAddress
    }

    private var roleIcon: String {
        if let role = health?.role {
            return GasTownRoleIcon.sfSymbol(for: role)
        }
        return "person.fill"
    }

    private var roleColor: Color {
        if let role = health?.role {
            return AgentRoleGroup.from(role: role).borderColor
        }
        return .secondary
    }

    @ViewBuilder
    private var statusDotView: some View {
        let color = statusColor
        let label = statusLabel

        Circle()
            .fill(color)
            .frame(width: GasTownStatusDot.size, height: GasTownStatusDot.size)
            .accessibilityLabel(String(
                localized: "agentProfile.statusDot.a11y",
                defaultValue: "Status"
            ))
            .accessibilityValue(label)

        Text(label)
            .font(GasTownTypography.caption)
            .foregroundColor(color)
    }

    private var statusColor: Color {
        guard let health else { return GasTownColors.idle }
        return health.statusColor
    }

    private var statusLabel: String {
        guard let health else {
            return String(localized: "agentProfile.status.unknown", defaultValue: "unknown")
        }
        return health.statusLabel
    }
}

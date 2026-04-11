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

                    // Three-layer architecture badges
                    architectureBadgeRow
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

            // Row 3: Session info
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

    // MARK: - Architecture Badges

    @ViewBuilder
    private var architectureBadgeRow: some View {
        if let health {
            HStack(spacing: 4) {
                // Session status badge
                architectureBadge(
                    icon: "terminal",
                    text: health.isRunning
                        ? String(localized: "agentProfile.session.active", defaultValue: "Session active")
                        : String(localized: "agentProfile.session.inactive", defaultValue: "No session"),
                    color: health.isRunning ? GasTownColors.active : GasTownColors.idle
                )

                // Sandbox path badge
                architectureBadge(
                    icon: "folder",
                    text: sandboxPath,
                    color: .secondary
                )

                // Slot name badge
                if let slotName = slotNameFromAddress {
                    architectureBadge(
                        icon: "square.grid.2x2",
                        text: slotName,
                        color: .secondary
                    )
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(
                localized: "agentProfile.architecture.a11y",
                defaultValue: "Agent architecture"
            ))
        }
    }

    private func architectureBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(text)
                .font(GasTownTypography.badge)
        }
        .foregroundColor(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }

    private var sandboxPath: String {
        // Derive sandbox path from agent address (e.g., "gmux/polecats/rust" → "polecats/rust")
        let components = agentAddress.split(separator: "/")
        if components.count >= 2 {
            return components.dropFirst().joined(separator: "/")
        }
        return agentAddress
    }

    private var slotNameFromAddress: String? {
        // Slot name is the last component of the address (e.g., "gmux/polecats/rust" → "rust")
        let components = agentAddress.split(separator: "/")
        guard components.count >= 3 else { return nil }
        return String(components.last!)
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

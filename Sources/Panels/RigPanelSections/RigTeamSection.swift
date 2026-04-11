import SwiftUI

/// Team section showing agents grouped by role with status dots, tasks, and context bars.
struct RigTeamSection: View {
    let agents: [AgentHealthEntry]
    @ObservedObject var panel: RigPanel

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let groups = panel.groupedAgents(from: agents)

        VStack(alignment: .leading, spacing: GasTownSpacing.gridGap) {
            // Section header
            HStack {
                Text(String(localized: "rigPanel.team.sectionTitle", defaultValue: "Team"))
                    .font(GasTownTypography.sectionHeader)
                Spacer()
                Text(String(
                    localized: "rigPanel.team.agentCount",
                    defaultValue: "\(agents.count) agents"
                ))
                .font(GasTownTypography.caption)
                .foregroundColor(.secondary)
            }

            // Agent groups
            ForEach(groups, id: \.group) { entry in
                if entry.group == .infrastructure {
                    infrastructureGroup(entry.agents)
                } else {
                    roleGroup(entry.group, agents: entry.agents)
                }
            }
        }
        .padding(GasTownSpacing.cardPadding)
        .background(GasTownColors.sectionBackground(for: colorScheme))
        .cornerRadius(8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(
            localized: "rigPanel.team.a11y",
            defaultValue: "Team section"
        ))
    }

    // MARK: - Role Group

    @ViewBuilder
    private func roleGroup(_ group: AgentRoleGroup, agents: [AgentHealthEntry]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.title)
                .font(GasTownTypography.badge)
                .foregroundColor(group.borderColor)
                .textCase(.uppercase)

            ForEach(agents) { agent in
                agentRow(agent)
            }
        }
        .padding(.leading, 4)
        .overlay(
            Rectangle()
                .fill(group.borderColor.opacity(0.3))
                .frame(width: 2),
            alignment: .leading
        )
    }

    // MARK: - Infrastructure (collapsible)

    @ViewBuilder
    private func infrastructureGroup(_ agents: [AgentHealthEntry]) -> some View {
        let runningCount = agents.filter(\.isRunning).count

        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(GasTownAnimation.statusChange) {
                    panel.infrastructureCollapsed.toggle()
                }
            } label: {
                HStack {
                    Text(AgentRoleGroup.infrastructure.title)
                        .font(GasTownTypography.badge)
                        .foregroundColor(AgentRoleGroup.infrastructure.borderColor)
                        .textCase(.uppercase)
                    Spacer()
                    Text(String(
                        localized: "rigPanel.team.infraSummary",
                        defaultValue: "\(runningCount)/\(agents.count) running"
                    ))
                    .font(GasTownTypography.caption)
                    .foregroundColor(.secondary)
                    Image(systemName: panel.infrastructureCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(
                localized: "rigPanel.team.infraToggle.a11y",
                defaultValue: "Infrastructure agents"
            ))
            .accessibilityValue(panel.infrastructureCollapsed
                ? String(
                    localized: "rigPanel.team.infraCollapsed.a11y",
                    defaultValue: "Collapsed, \(runningCount) of \(agents.count) running"
                )
                : String(
                    localized: "rigPanel.team.infraExpanded.a11y",
                    defaultValue: "Expanded"
                )
            )

            if !panel.infrastructureCollapsed {
                ForEach(agents) { agent in
                    agentRow(agent)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .padding(.leading, 4)
        .overlay(
            Rectangle()
                .fill(AgentRoleGroup.infrastructure.borderColor.opacity(0.3))
                .frame(width: 2),
            alignment: .leading
        )
    }

    // MARK: - Agent Row

    @ViewBuilder
    private func agentRow(_ agent: AgentHealthEntry) -> some View {
        HStack(spacing: GasTownSpacing.gridGap) {
            // Role icon
            Image(systemName: AgentRoleGroup.icon(for: agent.role))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 16)

            // Agent name (clickable link)
            AgentNameLink(name: agent.name, agentAddress: agent.address)

            // Status dot
            Circle()
                .fill(agentStatusColor(agent))
                .frame(width: GasTownStatusDot.size, height: GasTownStatusDot.size)
                .accessibilityLabel(String(
                    localized: "rigPanel.team.status.a11y",
                    defaultValue: "Status"
                ))
                .accessibilityValue(agentStatusLabel(agent))

            // Status label
            Text(agentStatusLabel(agent))
                .font(GasTownTypography.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            // Current task (bead ID + title)
            if let task = agent.currentTask {
                HStack(spacing: 2) {
                    Text(task)
                        .font(GasTownTypography.data)
                        .foregroundColor(.secondary)
                    if let title = agent.hookBeadTitle {
                        Text(title)
                            .font(GasTownTypography.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .lineLimit(1)
            }

            Spacer()

            // Context bar (if active)
            if let percent = agent.contextPercent {
                ContextBarView(percent: percent, maxWidth: 60)
                    .accessibilityLabel(String(
                        localized: "rigPanel.team.context.a11y",
                        defaultValue: "Context usage"
                    ))
                    .accessibilityValue(String(
                        localized: "rigPanel.team.contextValue.a11y",
                        defaultValue: "\(Int(percent * 100)) percent"
                    ))
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(
            localized: "rigPanel.team.agentRow.a11y",
            defaultValue: "Agent: \(agent.name), \(agent.role), \(agent.rig)"
        ))
        .accessibilityValue(String(
            localized: "rigPanel.team.agentRowValue.a11y",
            defaultValue: "\(agentStatusLabel(agent))\(agent.currentTask.map { ", working on \($0)" } ?? "")\(agent.contextPercent.map { ", context \(Int($0 * 100)) percent" } ?? "")"
        ))
    }

    // MARK: - Helpers

    private func agentStatusColor(_ agent: AgentHealthEntry) -> Color {
        agent.statusColor
    }

    private func agentStatusLabel(_ agent: AgentHealthEntry) -> String {
        agent.statusLabel
    }
}

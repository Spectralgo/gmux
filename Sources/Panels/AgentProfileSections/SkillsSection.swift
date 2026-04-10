import SwiftUI

/// Section showing derived skills as horizontal progress bars.
struct SkillsSection: View {
    let skills: [AgentSkill]
    let roleColor: Color

    @Environment(\.colorScheme) private var colorScheme
    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: GasTownSpacing.gridGap) {
            Text(String(localized: "agentProfile.skills.title", defaultValue: "Skills"))
                .font(GasTownTypography.sectionHeader)
                .accessibilityAddTraits(.isHeader)

            if skills.isEmpty {
                Text(String(localized: "agentProfile.skills.empty", defaultValue: "No skill data yet"))
                    .font(GasTownTypography.caption)
                    .foregroundColor(.secondary)
            } else {
                let displayed = showAll ? skills : Array(skills.prefix(4))
                ForEach(displayed) { skill in
                    skillBar(skill)
                }

                if skills.count > 4 && !showAll {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showAll = true
                        }
                    } label: {
                        Text(String(
                            localized: "agentProfile.skills.showAll",
                            defaultValue: "Show all (\(skills.count))"
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
            localized: "agentProfile.skills.section.a11y",
            defaultValue: "Skills section"
        ))
    }

    @ViewBuilder
    private func skillBar(_ skill: AgentSkill) -> some View {
        let maxTasks = skills.first?.taskCount ?? 1
        let fillFraction = maxTasks > 0 ? CGFloat(skill.taskCount) / CGFloat(maxTasks) : 0

        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(skill.category)
                    .font(GasTownTypography.label)
                Spacer()
                Text(String(
                    localized: "agentProfile.skills.taskCount",
                    defaultValue: "\(skill.taskCount) tasks"
                ))
                .font(GasTownTypography.caption)
                .foregroundColor(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(roleColor)
                        .frame(width: geo.size.width * fillFraction)
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(
            localized: "agentProfile.skills.bar.a11y",
            defaultValue: "\(skill.category): \(skill.taskCount) tasks, \(Int(skill.successRate * 100)) percent success rate"
        ))
    }
}

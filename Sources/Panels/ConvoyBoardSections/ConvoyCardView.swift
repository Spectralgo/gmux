import SwiftUI

/// Card for a single convoy in the board list.
///
/// Shows title, progress bar, issue counts, assigned polecats,
/// and attention badge. Clickable to select.
struct ConvoyCardView: View {
    let convoy: ConvoySummary
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: GasTownSpacing.gridGap) {
                // Title + attention badge
                HStack(spacing: 6) {
                    attentionDot
                    Text(convoy.title)
                        .font(GasTownTypography.label)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .foregroundColor(.primary)

                    Spacer()

                    statusBadge
                }

                // Progress bar
                progressBar

                // Stats row
                HStack(spacing: GasTownSpacing.gridGap) {
                    issueCount
                    Spacer()
                    polecatCount
                }
            }
            .padding(GasTownSpacing.cardPadding)
            .background(cardBackground)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
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
            localized: "convoyCard.a11y",
            defaultValue: "Convoy: \(convoy.title)"
        ))
        .accessibilityValue(String(
            localized: "convoyCard.progress.a11y",
            defaultValue: "\(Int(convoy.progress * 100)) percent, \(convoy.completedIssues) of \(convoy.totalIssues) issues"
        ))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Subviews

    @ViewBuilder
    private var attentionDot: some View {
        Circle()
            .fill(attentionColor)
            .frame(width: GasTownStatusDot.size, height: GasTownStatusDot.size)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if convoy.status == "closed" {
            Text(String(localized: "convoyCard.done", defaultValue: "done"))
                .font(GasTownTypography.badge)
                .foregroundColor(GasTownColors.active)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(GasTownColors.active.opacity(0.15))
                .cornerRadius(3)
        } else if convoy.attention == .stranded {
            Text(String(localized: "convoyCard.stranded", defaultValue: "stranded"))
                .font(GasTownTypography.badge)
                .foregroundColor(GasTownColors.attention)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(GasTownColors.attention.opacity(0.15))
                .cornerRadius(3)
        } else if convoy.attention == .blocked {
            Text(String(localized: "convoyCard.blocked", defaultValue: "blocked"))
                .font(GasTownTypography.badge)
                .foregroundColor(GasTownColors.error)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(GasTownColors.error.opacity(0.15))
                .cornerRadius(3)
        }
    }

    @ViewBuilder
    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.15))
                RoundedRectangle(cornerRadius: 3)
                    .fill(progressColor)
                    .frame(width: geo.size.width * min(max(convoy.progress, 0), 1))
                    .animation(GasTownAnimation.statusChange, value: convoy.progress)
            }
        }
        .frame(height: 8)
    }

    @ViewBuilder
    private var issueCount: some View {
        HStack(spacing: 3) {
            Image(systemName: "circle.dotted")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(String(
                localized: "convoyCard.issues",
                defaultValue: "\(convoy.completedIssues)/\(convoy.totalIssues)"
            ))
            .font(GasTownTypography.data)
            .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var polecatCount: some View {
        if convoy.assignedPolecats > 0 {
            HStack(spacing: 3) {
                Image(systemName: GasTownRoleIcons.polecat)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("\(convoy.assignedPolecats)")
                    .font(GasTownTypography.data)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Styling

    private var cardBackground: Color {
        GasTownColors.sectionBackground(for: colorScheme)
    }

    private var attentionColor: Color {
        switch convoy.attention {
        case .normal:
            return convoy.status == "closed" ? GasTownColors.idle : GasTownColors.active
        case .stranded:
            return GasTownColors.attention
        case .blocked:
            return GasTownColors.error
        }
    }

    private var progressColor: Color {
        if convoy.progress >= 1.0 { return GasTownColors.active }
        switch convoy.attention {
        case .normal: return Color.accentColor
        case .stranded: return GasTownColors.attention
        case .blocked: return GasTownColors.error
        }
    }
}

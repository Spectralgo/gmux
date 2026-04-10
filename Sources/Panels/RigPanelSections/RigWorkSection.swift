import SwiftUI

/// Work section showing bead counts and convoy progress bars.
struct RigWorkSection: View {
    let beadCounts: BeadCountSummary
    let convoys: [ConvoySummary]
    let workspaceId: UUID

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: GasTownSpacing.gridGap) {
            // Section header
            Text(String(localized: "rigPanel.work.sectionTitle", defaultValue: "Work"))
                .font(GasTownTypography.sectionHeader)

            // Bead counts
            HStack(spacing: GasTownSpacing.gridGap) {
                Text(String(
                    localized: "rigPanel.work.beadsLabel",
                    defaultValue: "Beads:"
                ))
                .font(GasTownTypography.label)
                .foregroundColor(.secondary)

                beadCountButton(
                    count: beadCounts.ready,
                    label: String(localized: "rigPanel.work.ready", defaultValue: "ready"),
                    filter: "ready"
                )

                Text("|")
                    .foregroundColor(.secondary)

                beadCountButton(
                    count: beadCounts.inProgress,
                    label: String(localized: "rigPanel.work.inProgress", defaultValue: "in-progress"),
                    filter: "in_progress"
                )

                Text("|")
                    .foregroundColor(.secondary)

                beadCountButton(
                    count: beadCounts.closed,
                    label: String(localized: "rigPanel.work.closed", defaultValue: "closed"),
                    filter: "closed"
                )

                Spacer()
            }

            // Convoys
            if !convoys.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "rigPanel.work.convoys", defaultValue: "Convoys:"))
                        .font(GasTownTypography.label)
                        .foregroundColor(.secondary)

                    ForEach(convoys) { convoy in
                        convoyRow(convoy)
                    }
                }
            }
        }
        .padding(GasTownSpacing.cardPadding)
        .background(GasTownColors.sectionBackground(for: colorScheme))
        .cornerRadius(8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(
            localized: "rigPanel.work.a11y",
            defaultValue: "Work section"
        ))
    }

    // MARK: - Bead Count Button

    @ViewBuilder
    private func beadCountButton(count: Int, label: String, filter: String) -> some View {
        Button {
            NotificationCenter.default.post(
                name: .openConvoyBoard,
                object: nil,
                userInfo: [
                    "filter": filter,
                    "workspaceId": workspaceId,
                ]
            )
        } label: {
            HStack(spacing: 2) {
                Text("\(count)")
                    .font(GasTownTypography.data)
                    .foregroundColor(.accentColor)
                Text(label)
                    .font(GasTownTypography.caption)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(
            localized: "rigPanel.work.beadCount.a11y",
            defaultValue: "\(label) beads"
        ))
        .accessibilityValue("\(count)")
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    // MARK: - Convoy Row

    @ViewBuilder
    private func convoyRow(_ convoy: ConvoySummary) -> some View {
        HStack(spacing: GasTownSpacing.gridGap) {
            Button {
                NotificationCenter.default.post(
                    name: .openConvoyBoard,
                    object: nil,
                    userInfo: [
                        "convoyId": convoy.id,
                        "workspaceId": workspaceId,
                    ]
                )
            } label: {
                Text("\"\(convoy.title)\"")
                    .font(GasTownTypography.label)
                    .foregroundColor(.accentColor)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }

            // Progress bar
            convoyProgressBar(convoy.progress)

            // Percentage or "done"
            if convoy.status == "closed" {
                Text(String(localized: "rigPanel.work.convoyDone", defaultValue: "done"))
                    .font(GasTownTypography.badge)
                    .foregroundColor(GasTownColors.active)
            } else {
                Text("\(Int(convoy.progress * 100))%")
                    .font(GasTownTypography.data)
                    .foregroundColor(.secondary)
            }

            // Attention badge
            if convoy.attention == .stranded {
                Text(String(localized: "rigPanel.work.stranded", defaultValue: "stranded"))
                    .font(GasTownTypography.badge)
                    .foregroundColor(GasTownColors.attention)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(GasTownColors.attention.opacity(0.15))
                    .cornerRadius(3)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(
            localized: "rigPanel.work.convoy.a11y",
            defaultValue: "Convoy: \(convoy.title)"
        ))
        .accessibilityValue(String(
            localized: "rigPanel.work.convoyProgress.a11y",
            defaultValue: "\(Int(convoy.progress * 100)) percent complete"
        ))
    }

    @ViewBuilder
    private func convoyProgressBar(_ progress: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.15))
                RoundedRectangle(cornerRadius: 2)
                    .fill(progress >= 1.0 ? GasTownColors.active : Color.accentColor)
                    .frame(width: geo.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 6)
        .frame(maxWidth: 120)
    }
}

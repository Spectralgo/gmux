import SwiftUI

/// Health section showing traffic-light indicators with expandable details.
struct RigHealthSection: View {
    let health: RigHealthIndicators
    @ObservedObject var panel: RigPanel

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: GasTownSpacing.gridGap) {
            Text(String(localized: "rigPanel.health.sectionTitle", defaultValue: "Health"))
                .font(GasTownTypography.sectionHeader)

            healthRow(
                name: "build",
                label: String(localized: "rigPanel.health.build", defaultValue: "Build"),
                signal: health.build
            )
            healthRow(
                name: "ci",
                label: String(localized: "rigPanel.health.ci", defaultValue: "CI"),
                signal: health.ci
            )
            healthRow(
                name: "dolt",
                label: String(localized: "rigPanel.health.dolt", defaultValue: "Dolt"),
                signal: health.dolt
            )
            healthRow(
                name: "disk",
                label: String(localized: "rigPanel.health.disk", defaultValue: "Disk"),
                signal: health.disk
            )
            doctorRow()
        }
        .padding(GasTownSpacing.cardPadding)
        .background(GasTownColors.sectionBackground(for: colorScheme))
        .cornerRadius(8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(
            localized: "rigPanel.health.a11y",
            defaultValue: "Health section"
        ))
    }

    // MARK: - Health Row

    @ViewBuilder
    private func healthRow(name: String, label: String, signal: HealthSignal) -> some View {
        let isExpanded = panel.expandedHealthRow == name

        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(GasTownAnimation.statusChange) {
                    panel.toggleHealthRow(name)
                }
            } label: {
                HStack(spacing: GasTownSpacing.gridGap) {
                    signalDot(signal)
                    Text(label)
                        .font(GasTownTypography.label)
                        .frame(width: 50, alignment: .leading)
                    Text(signal.message)
                        .font(GasTownTypography.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityValue(signal.message)

            if isExpanded {
                Text(signal.message)
                    .font(GasTownTypography.data)
                    .foregroundColor(.secondary)
                    .padding(.leading, GasTownStatusDot.size + GasTownSpacing.gridGap)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Doctor Row

    @ViewBuilder
    private func doctorRow() -> some View {
        let signal = health.doctorSignal
        let isExpanded = panel.expandedHealthRow == "doctor"

        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(GasTownAnimation.statusChange) {
                    panel.toggleHealthRow("doctor")
                }
            } label: {
                HStack(spacing: GasTownSpacing.gridGap) {
                    signalDot(signal)
                    Text(String(localized: "rigPanel.health.doctor", defaultValue: "Doctor"))
                        .font(GasTownTypography.label)
                        .frame(width: 50, alignment: .leading)
                    Text(signal.message)
                        .font(GasTownTypography.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(
                localized: "rigPanel.health.doctor.a11y",
                defaultValue: "Doctor"
            ))
            .accessibilityValue(signal.message)

            if isExpanded {
                doctorDetails()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private func doctorDetails() -> some View {
        let nonPassing = health.doctor.details.filter { $0.status != .pass }

        if nonPassing.isEmpty && health.doctor.details.isEmpty {
            Text(String(localized: "rigPanel.health.doctorNoData", defaultValue: "No doctor data available"))
                .font(GasTownTypography.caption)
                .foregroundColor(.secondary)
                .padding(.leading, GasTownStatusDot.size + GasTownSpacing.gridGap)
        } else if nonPassing.isEmpty {
            Text(String(localized: "rigPanel.health.doctorAllPass", defaultValue: "All checks passing"))
                .font(GasTownTypography.caption)
                .foregroundColor(GasTownColors.active)
                .padding(.leading, GasTownStatusDot.size + GasTownSpacing.gridGap)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(nonPassing) { check in
                    HStack(spacing: 4) {
                        Text(check.status == .fail ? "├─" : "├─")
                            .font(GasTownTypography.data)
                            .foregroundColor(.secondary)
                        Text("[\(check.status.rawValue)]")
                            .font(GasTownTypography.badge)
                            .foregroundColor(check.status == .fail ? GasTownColors.error : GasTownColors.attention)
                        Text(check.message.isEmpty ? check.name : check.message)
                            .font(GasTownTypography.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.leading, GasTownStatusDot.size + GasTownSpacing.gridGap)
        }
    }

    // MARK: - Signal Dot

    @ViewBuilder
    private func signalDot(_ signal: HealthSignal) -> some View {
        Circle()
            .fill(colorForSignal(signal))
            .frame(width: GasTownStatusDot.size, height: GasTownStatusDot.size)
    }

    private func colorForSignal(_ signal: HealthSignal) -> Color {
        switch signal {
        case .green: return GasTownColors.active
        case .amber: return GasTownColors.attention
        case .red: return GasTownColors.error
        case .unknown: return GasTownColors.idle
        }
    }
}

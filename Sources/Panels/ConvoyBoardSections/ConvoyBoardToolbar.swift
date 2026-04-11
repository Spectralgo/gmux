import SwiftUI

/// Toolbar for the Convoy Board showing title, convoy count, and toggles.
struct ConvoyBoardToolbar: View {
    @ObservedObject var panel: ConvoyBoardPanel

    var body: some View {
        HStack(spacing: GasTownSpacing.gridGap) {
            Image(systemName: "shippingbox")
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            Text(String(localized: "convoyBoard.toolbar.title", defaultValue: "Convoys"))
                .font(GasTownTypography.sectionHeader)

            // Convoy count badge
            Text("\(panel.convoys.count)")
                .font(GasTownTypography.badge)
                .foregroundColor(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(3)

            // Attention count
            if !panel.attentionConvoys.isEmpty {
                HStack(spacing: 3) {
                    Circle()
                        .fill(GasTownColors.attention)
                        .frame(width: 6, height: 6)
                    Text(String(
                        localized: "convoyBoard.toolbar.attention",
                        defaultValue: "\(panel.attentionConvoys.count) need attention"
                    ))
                    .font(GasTownTypography.caption)
                    .foregroundColor(GasTownColors.attention)
                }
            }

            Spacer()

            // Show closed toggle
            Toggle(isOn: $panel.showClosed) {
                Text(String(localized: "convoyBoard.toolbar.showClosed", defaultValue: "Show closed"))
                    .font(GasTownTypography.caption)
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .onChange(of: panel.showClosed) { _ in
                panel.refresh(silent: true)
            }

            // Manual refresh
            Button {
                panel.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .accessibilityLabel(String(
                localized: "convoyBoard.toolbar.refresh.a11y",
                defaultValue: "Refresh convoys"
            ))
        }
        .padding(.horizontal, GasTownSpacing.rowPaddingH)
        .padding(.vertical, GasTownSpacing.rowPaddingV)
    }
}

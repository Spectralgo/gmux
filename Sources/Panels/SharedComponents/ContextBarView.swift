import SwiftUI

/// A 4px progress bar with green/amber/red gradient at 60%/80% thresholds.
///
/// Extracted from ``TownDashboardPanelView`` for reuse across panels
/// (Agent Profile, Rig Panel, etc.).
///
/// **Design spec:**
/// - Height: 4px, corner radius: 2px
/// - Color: ``GasTownColors/active`` (0–60%), ``GasTownColors/attention`` (60–80%),
///   ``GasTownColors/error`` (80–100%)
/// - Track: `.secondary.opacity(0.15)`
struct ContextBarView: View {
    let percent: Double
    var maxWidth: CGFloat = 120

    var body: some View {
        let clamped = min(max(percent, 0), 1)
        let barColor: Color = clamped < 0.6 ? GasTownColors.active
            : clamped < 0.8 ? GasTownColors.attention
            : GasTownColors.error

        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.15))
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor)
                    .frame(width: geo.size.width * clamped)
            }
        }
        .frame(height: 4)
        .frame(maxWidth: maxWidth)
    }
}

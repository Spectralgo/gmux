import SwiftUI
import Foundation

/// Root view for the Engine Room (Diagnostics) panel.
///
/// Shows traffic lights bar, expandable detail sections for system, agents,
/// and storage. Starts/stops ``DiagnosticsStore`` polling on appear/disappear.
struct DiagnosticsPanelView: View {
    @ObservedObject var panel: DiagnosticsPanel
    let isFocused: Bool
    let isVisibleInUI: Bool
    let portalPriority: Int
    let onRequestPanelFocus: () -> Void

    @State private var focusFlashOpacity: Double = 0.0
    @State private var focusFlashAnimationGeneration: Int = 0
    @State private var expandedSection: DiagnosticsDomain?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: GasTownSpacing.sectionGap) {
                TrafficLightsBar(
                    systemStatus: panel.store.systemStatus,
                    agentsStatus: panel.store.agentsStatus,
                    storageStatus: panel.store.storageStatus,
                    expandedSection: $expandedSection
                )

                if expandedSection == .system {
                    SystemDetailSection(details: panel.store.systemDetails)
                }

                if expandedSection == .agents {
                    AgentsDetailSection(details: panel.store.agentsDetails)
                }

                if expandedSection == .storage {
                    StorageDetailSection(details: panel.store.storageDetails)
                }

                if let lastRefresh = panel.store.lastRefresh {
                    HStack {
                        Spacer()
                        Text(String(
                            localized: "diagnostics.lastRefresh",
                            defaultValue: "Updated \(relativeTime(lastRefresh))"
                        ))
                        .font(GasTownTypography.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, GasTownSpacing.rowPaddingH)
                }
            }
            .padding(GasTownSpacing.cardPadding)
        }
        .background(GasTownColors.panelBackground(for: colorScheme))
        .overlay {
            RoundedRectangle(cornerRadius: FocusFlashPattern.ringCornerRadius)
                .stroke(cmuxAccentColor().opacity(focusFlashOpacity), lineWidth: 3)
                .shadow(color: cmuxAccentColor().opacity(focusFlashOpacity * 0.35), radius: 10)
                .padding(FocusFlashPattern.ringInset)
                .allowsHitTesting(false)
        }
        .overlay {
            if isVisibleInUI {
                DiagnosticsPointerObserver(onPointerDown: onRequestPanelFocus)
            }
        }
        .onChange(of: panel.focusFlashToken) { _ in
            triggerFocusFlashAnimation()
        }
        .onAppear {
            panel.store.startPolling()
        }
        .onDisappear {
            panel.store.stopPolling()
        }
    }

    // MARK: - Focus Flash

    private func triggerFocusFlashAnimation() {
        focusFlashAnimationGeneration &+= 1
        let generation = focusFlashAnimationGeneration
        focusFlashOpacity = FocusFlashPattern.values.first ?? 0

        for segment in FocusFlashPattern.segments {
            DispatchQueue.main.asyncAfter(deadline: .now() + segment.delay) {
                guard focusFlashAnimationGeneration == generation else { return }
                withAnimation(focusFlashAnimation(for: segment.curve, duration: segment.duration)) {
                    focusFlashOpacity = segment.targetOpacity
                }
            }
        }
    }
}

// MARK: - Diagnostics Domain

enum DiagnosticsDomain {
    case system
    case agents
    case storage
}

// MARK: - Traffic Lights Bar

private struct TrafficLightsBar: View {
    let systemStatus: TrafficLight
    let agentsStatus: TrafficLight
    let storageStatus: TrafficLight
    @Binding var expandedSection: DiagnosticsDomain?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: GasTownSpacing.gridGap) {
            TrafficLightIndicator(
                domain: .system,
                label: String(localized: "diagnostics.system", defaultValue: "System"),
                status: systemStatus,
                isExpanded: expandedSection == .system
            ) {
                toggleSection(.system)
            }
            TrafficLightIndicator(
                domain: .agents,
                label: String(localized: "diagnostics.agents", defaultValue: "Agents"),
                status: agentsStatus,
                isExpanded: expandedSection == .agents
            ) {
                toggleSection(.agents)
            }
            TrafficLightIndicator(
                domain: .storage,
                label: String(localized: "diagnostics.storage", defaultValue: "Storage"),
                status: storageStatus,
                isExpanded: expandedSection == .storage
            ) {
                toggleSection(.storage)
            }
        }
        .padding(GasTownSpacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(GasTownColors.sectionBackground(for: colorScheme))
        )
    }

    private func toggleSection(_ domain: DiagnosticsDomain) {
        withAnimation(GasTownAnimation.statusChange) {
            if expandedSection == domain {
                expandedSection = nil
            } else {
                expandedSection = domain
            }
        }
    }
}

// MARK: - Traffic Light Indicator

private struct TrafficLightIndicator: View {
    let domain: DiagnosticsDomain
    let label: String
    let status: TrafficLight
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Circle()
                    .fill(trafficLightColor(for: status))
                    .frame(width: 24, height: 24)

                Text(label)
                    .font(GasTownTypography.label)
                    .foregroundColor(.primary)

                Text(status.displayLabel)
                    .font(GasTownTypography.caption)
                    .foregroundColor(trafficLightColor(for: status))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, GasTownSpacing.rowPaddingV)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - System Detail Section

private struct SystemDetailSection: View {
    let details: SystemDetails?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: String(localized: "diagnostics.system.detail", defaultValue: "System Details"))

            if let d = details {
                SubCheckRow(
                    icon: d.doltServer != nil ? "checkmark.circle.fill" : "xmark.circle.fill",
                    iconColor: d.doltServer != nil ? GasTownColors.active : GasTownColors.error,
                    label: String(localized: "diagnostics.doltServer", defaultValue: "Dolt Server"),
                    value: doltServerValue(d.doltServer)
                )

                SubCheckRow(
                    icon: d.daemonRunning ? "checkmark.circle.fill" : "xmark.circle.fill",
                    iconColor: d.daemonRunning ? GasTownColors.active : GasTownColors.error,
                    label: String(localized: "diagnostics.daemon", defaultValue: "Daemon"),
                    value: daemonValue(d)
                )

                SubCheckRow(
                    icon: d.bootWatchdogHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    iconColor: d.bootWatchdogHealthy ? GasTownColors.active : GasTownColors.attention,
                    label: String(localized: "diagnostics.bootWatchdog", defaultValue: "Boot Watchdog"),
                    value: d.bootWatchdogHealthy
                        ? String(localized: "diagnostics.healthy", defaultValue: "Healthy")
                        : String(localized: "diagnostics.unhealthy", defaultValue: "Unhealthy")
                )

                SubCheckRow(
                    icon: doltGapIcon(d.doltCommitGap),
                    iconColor: doltGapColor(d.doltCommitGap),
                    label: String(localized: "diagnostics.doltCommitGap", defaultValue: "Dolt Commit Gap"),
                    value: formatDuration(d.doltCommitGap)
                )
            } else {
                noDataRow
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(GasTownColors.sectionBackground(for: colorScheme))
        )
    }

    private func doltServerValue(_ info: DoltServerInfo?) -> String {
        guard let info else {
            return String(localized: "diagnostics.notRunning", defaultValue: "Not running")
        }
        return "PID \(info.pid) · \(info.connections)/\(info.maxConnections) conns · \(String(format: "%.0f", info.memoryMB)) MB"
    }

    private func daemonValue(_ d: SystemDetails) -> String {
        if let pid = d.daemonPID, d.daemonRunning {
            return "PID \(pid)"
        }
        return String(localized: "diagnostics.notRunning", defaultValue: "Not running")
    }

    private func doltGapIcon(_ gap: TimeInterval?) -> String {
        guard let gap else { return "questionmark.circle" }
        if gap > 3600 { return "exclamationmark.triangle.fill" }
        return "checkmark.circle.fill"
    }

    private func doltGapColor(_ gap: TimeInterval?) -> Color {
        guard let gap else { return GasTownColors.idle }
        if gap > 3600 { return GasTownColors.attention }
        return GasTownColors.active
    }
}

// MARK: - Agents Detail Section

private struct AgentsDetailSection: View {
    let details: AgentsDetails?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: String(localized: "diagnostics.agents.detail", defaultValue: "Agents Details"))

            if let a = details {
                SubCheckRow(
                    icon: "person.2.fill",
                    iconColor: .primary,
                    label: String(localized: "diagnostics.activeSessions", defaultValue: "Active Sessions"),
                    value: "\(a.activeSessions)"
                )

                SubCheckRow(
                    icon: a.deadSessions > 0 ? "xmark.circle.fill" : "checkmark.circle.fill",
                    iconColor: a.deadSessions > 0 ? GasTownColors.error : GasTownColors.active,
                    label: String(localized: "diagnostics.deadSessions", defaultValue: "Dead Sessions"),
                    value: "\(a.deadSessions)"
                )

                SubCheckRow(
                    icon: a.zombieSessionCount > 0 ? "xmark.circle.fill" : "checkmark.circle.fill",
                    iconColor: a.zombieSessionCount > 0 ? GasTownColors.error : GasTownColors.active,
                    label: String(localized: "diagnostics.zombieSessions", defaultValue: "Zombie Sessions"),
                    value: "\(a.zombieSessionCount)"
                )

                SubCheckRow(
                    icon: a.orphanProcessCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                    iconColor: a.orphanProcessCount > 0 ? GasTownColors.attention : GasTownColors.active,
                    label: String(localized: "diagnostics.orphanProcesses", defaultValue: "Orphan Processes"),
                    value: "\(a.orphanProcessCount)"
                )

                SubCheckRow(
                    icon: a.stuckPatrolCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                    iconColor: a.stuckPatrolCount > 0 ? GasTownColors.attention : GasTownColors.active,
                    label: String(localized: "diagnostics.stuckPatrols", defaultValue: "Stuck Patrols"),
                    value: "\(a.stuckPatrolCount)"
                )

                if !a.sessionNames.isEmpty {
                    HStack {
                        Text(String(localized: "diagnostics.sessions", defaultValue: "Sessions"))
                            .font(GasTownTypography.label)
                        Spacer()
                        Text(a.sessionNames.joined(separator: ", "))
                            .font(GasTownTypography.data)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, GasTownSpacing.rowPaddingH)
                    .padding(.vertical, GasTownSpacing.rowPaddingV)
                }
            } else {
                noDataRow
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(GasTownColors.sectionBackground(for: colorScheme))
        )
    }
}

// MARK: - Storage Detail Section

private struct StorageDetailSection: View {
    let details: StorageDetails?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: String(localized: "diagnostics.storage.detail", defaultValue: "Storage Details"))

            if let s = details, s.diskTotal > 0 {
                let freePercent = Double(s.diskFree) / Double(max(s.diskTotal, 1))
                let diskIcon = freePercent < 0.05 ? "xmark.circle.fill"
                    : freePercent < 0.10 ? "exclamationmark.triangle.fill"
                    : "checkmark.circle.fill"
                let diskColor = freePercent < 0.05 ? GasTownColors.error
                    : freePercent < 0.10 ? GasTownColors.attention
                    : GasTownColors.active

                SubCheckRow(
                    icon: diskIcon,
                    iconColor: diskColor,
                    label: String(localized: "diagnostics.diskUsage", defaultValue: "Disk Usage"),
                    value: "\(formatBytes(s.diskTotal - s.diskFree)) / \(formatBytes(s.diskTotal)) (\(formatPercent(1 - freePercent)) used)"
                )

                SubCheckRow(
                    icon: diskFreeIcon(freePercent),
                    iconColor: diskColor,
                    label: String(localized: "diagnostics.diskFree", defaultValue: "Disk Free"),
                    value: "\(formatBytes(s.diskFree)) (\(formatPercent(freePercent)))"
                )

                if let ddSize = s.derivedDataSize {
                    let ddAmber = ddSize > 20_000_000_000
                    SubCheckRow(
                        icon: ddAmber ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                        iconColor: ddAmber ? GasTownColors.attention : GasTownColors.active,
                        label: String(localized: "diagnostics.derivedData", defaultValue: "DerivedData"),
                        value: formatBytes(ddSize)
                    )
                }

                if let bcSize = s.buildCacheSize {
                    let bcAmber = bcSize > 50_000_000_000
                    SubCheckRow(
                        icon: bcAmber ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                        iconColor: bcAmber ? GasTownColors.attention : GasTownColors.active,
                        label: String(localized: "diagnostics.buildCache", defaultValue: "Build Cache"),
                        value: formatBytes(bcSize)
                    )
                }

                if let doltSize = s.doltDataSize {
                    SubCheckRow(
                        icon: "internaldrive",
                        iconColor: .primary,
                        label: String(localized: "diagnostics.doltData", defaultValue: "Dolt Data"),
                        value: formatBytes(doltSize)
                    )
                }
            } else {
                noDataRow
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(GasTownColors.sectionBackground(for: colorScheme))
        )
    }

    private func diskFreeIcon(_ freePercent: Double) -> String {
        if freePercent < 0.05 { return "xmark.circle.fill" }
        if freePercent < 0.10 { return "exclamationmark.triangle.fill" }
        return "checkmark.circle.fill"
    }
}

// MARK: - Shared Sub-Components

private struct SectionHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(GasTownTypography.sectionHeader)
            Spacer()
        }
        .padding(.horizontal, GasTownSpacing.rowPaddingH)
        .padding(.vertical, GasTownSpacing.rowPaddingV)
    }
}

private struct SubCheckRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.system(size: 12))
            Text(label)
                .font(GasTownTypography.label)
            Spacer()
            Text(value)
                .font(GasTownTypography.data)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, GasTownSpacing.rowPaddingH)
        .padding(.vertical, GasTownSpacing.rowPaddingV)
    }
}

private var noDataRow: some View {
    HStack {
        Spacer()
        Text(String(localized: "diagnostics.noData", defaultValue: "No data yet"))
            .font(GasTownTypography.caption)
            .foregroundColor(.secondary)
        Spacer()
    }
    .padding(GasTownSpacing.rowPaddingV)
}

// MARK: - Formatting Helpers

private func trafficLightColor(for status: TrafficLight) -> Color {
    switch status {
    case .unknown: return GasTownColors.idle
    case .green: return GasTownColors.active
    case .amber: return GasTownColors.attention
    case .red: return GasTownColors.error
    }
}

private func formatBytes(_ bytes: UInt64) -> String {
    let gb = Double(bytes) / 1_073_741_824
    if gb >= 1.0 {
        return String(format: "%.1f GB", gb)
    }
    let mb = Double(bytes) / 1_048_576
    return String(format: "%.0f MB", mb)
}

private func formatPercent(_ value: Double) -> String {
    String(format: "%.0f%%", value * 100)
}

private func formatDuration(_ interval: TimeInterval?) -> String {
    guard let interval else {
        return String(localized: "diagnostics.unknown", defaultValue: "Unknown")
    }
    if interval < 60 {
        return String(format: "%.0fs", interval)
    }
    if interval < 3600 {
        return String(format: "%.0fm", interval / 60)
    }
    return String(format: "%.1fh", interval / 3600)
}

private func relativeTime(_ date: Date) -> String {
    let seconds = -date.timeIntervalSinceNow
    if seconds < 5 { return String(localized: "diagnostics.justNow", defaultValue: "just now") }
    if seconds < 60 { return String(format: "%.0fs ago", seconds) }
    if seconds < 3600 { return String(format: "%.0fm ago", seconds / 60) }
    return String(format: "%.0fh ago", seconds / 3600)
}

// MARK: - Pointer Observer

private struct DiagnosticsPointerObserver: NSViewRepresentable {
    let onPointerDown: () -> Void

    func makeNSView(context: Context) -> DiagnosticsPointerObserverView {
        let view = DiagnosticsPointerObserverView()
        view.onPointerDown = onPointerDown
        return view
    }

    func updateNSView(_ nsView: DiagnosticsPointerObserverView, context: Context) {
        nsView.onPointerDown = onPointerDown
    }
}

final class DiagnosticsPointerObserverView: NSView {
    var onPointerDown: (() -> Void)?
    private var eventMonitor: Any?

    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.handleEventIfNeeded(event) ?? event
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard PaneFirstClickFocusSettings.isEnabled() else { return nil }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        PaneFirstClickFocusSettings.isEnabled()
    }

    private func handleEventIfNeeded(_ event: NSEvent) -> NSEvent? {
        guard let window = self.window,
              event.window === window else { return event }
        let locationInSelf = convert(event.locationInWindow, from: nil)
        guard bounds.contains(locationInSelf) else { return event }
        onPointerDown?()
        return event
    }
}

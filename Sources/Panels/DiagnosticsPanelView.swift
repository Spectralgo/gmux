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

                WatchdogChainView(chain: panel.store.watchdogChain)

                EscalationQueueView(
                    escalations: panel.store.escalations,
                    onAcknowledge: { id in
                        Task { await panel.store.acknowledgeEscalation(id: id) }
                    },
                    onResolve: { id in
                        Task { await panel.store.resolveEscalation(id: id) }
                    }
                )

                if expandedSection == .system {
                    SystemDetailSection(
                        details: panel.store.systemDetails,
                        store: panel.store
                    )
                }

                if expandedSection == .agents {
                    AgentsDetailSection(details: panel.store.agentsDetails)
                }

                if expandedSection == .storage {
                    StorageDetailSection(
                        details: panel.store.storageDetails,
                        store: panel.store
                    )
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

    private func focusFlashAnimation(for curve: FocusFlashCurve, duration: TimeInterval) -> Animation {
        switch curve {
        case .easeIn:
            return .easeIn(duration: duration)
        case .easeOut:
            return .easeOut(duration: duration)
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
    let store: DiagnosticsStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var doltActionInProgress = false

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: String(localized: "diagnostics.system.detail", defaultValue: "System Details"))

            if let d = details {
                ActionSubCheckRow(
                    icon: d.doltServer != nil ? "checkmark.circle.fill" : "xmark.circle.fill",
                    iconColor: d.doltServer != nil ? GasTownColors.active : GasTownColors.error,
                    label: String(localized: "diagnostics.doltServer", defaultValue: "Dolt Server"),
                    value: doltServerValue(d.doltServer),
                    actionLabel: d.doltServer != nil
                        ? String(localized: "diagnostics.restartDolt", defaultValue: "Restart")
                        : String(localized: "diagnostics.startDolt", defaultValue: "Start"),
                    isLoading: doltActionInProgress
                ) {
                    doltActionInProgress = true
                    Task {
                        if d.doltServer != nil {
                            _ = await store.restartDolt()
                        } else {
                            _ = await store.startDolt()
                        }
                        doltActionInProgress = false
                    }
                }

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
                    icon: d.deaconHeartbeatFresh ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    iconColor: d.deaconHeartbeatFresh ? GasTownColors.active : GasTownColors.attention,
                    label: String(localized: "diagnostics.deaconHeartbeat", defaultValue: "Deacon Heartbeat"),
                    value: d.deaconHeartbeatFresh
                        ? String(localized: "diagnostics.fresh", defaultValue: "Fresh")
                        : String(localized: "diagnostics.stale", defaultValue: "Stale")
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
    let store: DiagnosticsStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var cleanDDInProgress = false
    @State private var cleanBCInProgress = false

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
                    ActionSubCheckRow(
                        icon: ddAmber ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                        iconColor: ddAmber ? GasTownColors.attention : GasTownColors.active,
                        label: String(localized: "diagnostics.derivedData", defaultValue: "DerivedData"),
                        value: formatBytes(ddSize),
                        actionLabel: String(localized: "diagnostics.clean", defaultValue: "Clean"),
                        isLoading: cleanDDInProgress
                    ) {
                        cleanDDInProgress = true
                        Task {
                            _ = await store.cleanDerivedData()
                            cleanDDInProgress = false
                        }
                    }
                }

                if let bcSize = s.buildCacheSize {
                    let bcAmber = bcSize > 50_000_000_000
                    ActionSubCheckRow(
                        icon: bcAmber ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                        iconColor: bcAmber ? GasTownColors.attention : GasTownColors.active,
                        label: String(localized: "diagnostics.buildCache", defaultValue: "Build Cache"),
                        value: formatBytes(bcSize),
                        actionLabel: String(localized: "diagnostics.clean", defaultValue: "Clean"),
                        isLoading: cleanBCInProgress
                    ) {
                        cleanBCInProgress = true
                        Task {
                            _ = await store.cleanBuildCache()
                            cleanBCInProgress = false
                        }
                    }
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

// MARK: - Watchdog Chain View

private struct WatchdogChainView: View {
    let chain: WatchdogChainState?
    @Environment(\.colorScheme) private var colorScheme
    @State private var expandedTier: WatchdogTier?

    enum WatchdogTier {
        case daemon, boot, deacon
    }

    var body: some View {
        VStack(spacing: GasTownSpacing.gridGap) {
            HStack(spacing: 0) {
                WatchdogTierNode(
                    tierName: String(localized: "diagnostics.daemon", defaultValue: "Daemon"),
                    metric: daemonMetric,
                    statusColor: daemonStatusColor,
                    statusLabel: daemonStatusLabel,
                    isExpanded: expandedTier == .daemon
                ) {
                    toggleTier(.daemon)
                }

                watchdogArrow(color: bootArrowColor)

                WatchdogTierNode(
                    tierName: String(localized: "diagnostics.boot", defaultValue: "Boot"),
                    metric: bootMetric,
                    statusColor: bootStatusColor,
                    statusLabel: bootStatusLabel,
                    isExpanded: expandedTier == .boot
                ) {
                    toggleTier(.boot)
                }

                watchdogArrow(color: deaconArrowColor)

                WatchdogTierNode(
                    tierName: String(localized: "diagnostics.deacon", defaultValue: "Deacon"),
                    metric: deaconMetric,
                    statusColor: deaconStatusColor,
                    statusLabel: deaconStatusLabel,
                    isExpanded: expandedTier == .deacon
                ) {
                    toggleTier(.deacon)
                }
            }

            if let chain {
                if expandedTier == .daemon {
                    DaemonDetail(daemon: chain.daemon)
                }
                if expandedTier == .boot {
                    BootDetail(boot: chain.boot)
                }
                if expandedTier == .deacon {
                    DeaconDetail(deacon: chain.deacon)
                }
            }
        }
        .padding(GasTownSpacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(GasTownColors.sectionBackground(for: colorScheme))
        )
    }

    private func toggleTier(_ tier: WatchdogTier) {
        withAnimation(GasTownAnimation.statusChange) {
            expandedTier = expandedTier == tier ? nil : tier
        }
    }

    private func watchdogArrow(color: Color) -> some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 12))
            .foregroundColor(color)
            .frame(width: 24)
    }

    // MARK: - Daemon computed properties

    private var daemonMetric: String {
        guard let chain else { return "—" }
        if let pid = chain.daemon.pid { return "PID \(pid)" }
        return String(localized: "diagnostics.notRunning", defaultValue: "Not running")
    }

    private var daemonStatusColor: Color {
        guard let chain else { return GasTownColors.idle }
        return chain.daemon.running ? GasTownColors.active : GasTownColors.error
    }

    private var daemonStatusLabel: String {
        guard let chain else {
            return String(localized: "diagnostics.unknown.short", defaultValue: "Unknown")
        }
        return chain.daemon.running
            ? String(localized: "diagnostics.running", defaultValue: "Running")
            : String(localized: "diagnostics.stopped", defaultValue: "Stopped")
    }

    // MARK: - Boot computed properties

    private var bootMetric: String {
        guard let chain else { return "—" }
        return chain.boot.lastDecision.rawValue
    }

    private var bootStatusColor: Color {
        guard let chain else { return GasTownColors.idle }
        switch chain.boot.lastDecision {
        case .nothing: return GasTownColors.active
        case .nudge: return GasTownColors.attention
        case .wake, .start: return GasTownColors.error
        case .unknown: return GasTownColors.idle
        }
    }

    private var bootStatusLabel: String {
        guard let chain else {
            return String(localized: "diagnostics.unknown.short", defaultValue: "Unknown")
        }
        switch chain.boot.lastDecision {
        case .nothing: return String(localized: "diagnostics.healthy", defaultValue: "Healthy")
        case .nudge: return String(localized: "diagnostics.nudged", defaultValue: "Nudged")
        case .wake: return String(localized: "diagnostics.waking", defaultValue: "Waking")
        case .start: return String(localized: "diagnostics.starting", defaultValue: "Starting")
        case .unknown: return String(localized: "diagnostics.unknown.short", defaultValue: "Unknown")
        }
    }

    private var bootArrowColor: Color { bootStatusColor }

    // MARK: - Deacon computed properties

    private var deaconMetric: String {
        guard let chain else { return "—" }
        if let age = chain.deacon.heartbeatAge {
            return formatDuration(age)
        }
        return "—"
    }

    private var deaconStatusColor: Color {
        guard let chain else { return GasTownColors.idle }
        if !chain.deacon.sessionAlive { return GasTownColors.error }
        if let age = chain.deacon.heartbeatAge, age > 300 { return GasTownColors.attention }
        return GasTownColors.active
    }

    private var deaconStatusLabel: String {
        guard let chain else {
            return String(localized: "diagnostics.unknown.short", defaultValue: "Unknown")
        }
        if !chain.deacon.sessionAlive {
            return String(localized: "diagnostics.dead", defaultValue: "Dead")
        }
        if let age = chain.deacon.heartbeatAge, age > 300 {
            return String(localized: "diagnostics.stale", defaultValue: "Stale")
        }
        return String(localized: "diagnostics.alive", defaultValue: "Alive")
    }

    private var deaconArrowColor: Color { deaconStatusColor }
}

// MARK: - Watchdog Tier Node

private struct WatchdogTierNode: View {
    let tierName: String
    let metric: String
    let statusColor: Color
    let statusLabel: String
    let isExpanded: Bool
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text(tierName)
                    .font(GasTownTypography.sectionHeader)
                Text(metric)
                    .font(GasTownTypography.data)
                    .foregroundColor(.secondary)
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: GasTownStatusDot.size, height: GasTownStatusDot.size)
                    Text(statusLabel)
                        .font(GasTownTypography.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, GasTownSpacing.rowPaddingV)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isExpanded ? GasTownColors.panelBackground(for: colorScheme) : .clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Watchdog Detail Views

private struct DaemonDetail: View {
    let daemon: DaemonState

    var body: some View {
        VStack(spacing: 0) {
            SubCheckRow(
                icon: "number",
                iconColor: .primary,
                label: String(localized: "diagnostics.pid", defaultValue: "PID"),
                value: daemon.pid.map { "\($0)" } ?? "—"
            )
            SubCheckRow(
                icon: "clock",
                iconColor: .primary,
                label: String(localized: "diagnostics.tickInterval", defaultValue: "Tick Interval"),
                value: "\(Int(daemon.tickInterval))s"
            )
        }
    }
}

private struct BootDetail: View {
    let boot: BootState

    var body: some View {
        VStack(spacing: 0) {
            SubCheckRow(
                icon: "clock",
                iconColor: .primary,
                label: String(localized: "diagnostics.lastFire", defaultValue: "Last Fire"),
                value: boot.lastFireTime.map { relativeTime($0) } ?? "—"
            )
            SubCheckRow(
                icon: "arrow.triangle.branch",
                iconColor: .primary,
                label: String(localized: "diagnostics.decision", defaultValue: "Decision"),
                value: boot.lastDecision.rawValue.uppercased()
            )
            if let reason = boot.lastReason {
                SubCheckRow(
                    icon: "text.quote",
                    iconColor: .primary,
                    label: String(localized: "diagnostics.reason", defaultValue: "Reason"),
                    value: reason
                )
            }
        }
    }
}

private struct DeaconDetail: View {
    let deacon: DeaconState

    var body: some View {
        VStack(spacing: 0) {
            SubCheckRow(
                icon: deacon.sessionAlive ? "checkmark.circle.fill" : "xmark.circle.fill",
                iconColor: deacon.sessionAlive ? GasTownColors.active : GasTownColors.error,
                label: String(localized: "diagnostics.session", defaultValue: "Session"),
                value: deacon.sessionAlive
                    ? String(localized: "diagnostics.alive", defaultValue: "Alive")
                    : String(localized: "diagnostics.dead", defaultValue: "Dead")
            )
            SubCheckRow(
                icon: "clock",
                iconColor: .primary,
                label: String(localized: "diagnostics.heartbeat", defaultValue: "Heartbeat"),
                value: deacon.lastHeartbeat.map { relativeTime($0) } ?? "—"
            )
            SubCheckRow(
                icon: deacon.patrolActive ? "checkmark.circle.fill" : "minus.circle",
                iconColor: deacon.patrolActive ? GasTownColors.active : GasTownColors.idle,
                label: String(localized: "diagnostics.patrol", defaultValue: "Patrol"),
                value: deacon.patrolActive
                    ? String(localized: "diagnostics.active", defaultValue: "Active")
                    : String(localized: "diagnostics.inactive", defaultValue: "Inactive")
            )
        }
    }
}

// MARK: - Escalation Queue View

private struct EscalationQueueView: View {
    let escalations: [EscalationEntry]
    let onAcknowledge: (String) -> Void
    let onResolve: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            if escalations.isEmpty {
                HStack(spacing: 4) {
                    Text(String(localized: "diagnostics.escalations.none", defaultValue: "Escalations: None open"))
                        .font(GasTownTypography.label)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11))
                        .foregroundColor(GasTownColors.active)
                    Spacer()
                }
                .padding(.horizontal, GasTownSpacing.rowPaddingH)
                .padding(.vertical, GasTownSpacing.rowPaddingV)
            } else {
                let unackCount = escalations.filter { !$0.acknowledged }.count
                SectionHeader(title: String(
                    localized: "diagnostics.escalations.header",
                    defaultValue: "Escalations (\(escalations.count) open · \(unackCount) unacknowledged)"
                ))

                ForEach(escalations) { entry in
                    EscalationRow(
                        entry: entry,
                        onAcknowledge: { onAcknowledge(entry.id) },
                        onResolve: { onResolve(entry.id) }
                    )
                    if entry.id != escalations.last?.id {
                        Divider()
                            .padding(.horizontal, GasTownSpacing.rowPaddingH)
                    }
                }
            }
        }
        .padding(.vertical, escalations.isEmpty ? 0 : GasTownSpacing.rowPaddingV)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(GasTownColors.sectionBackground(for: colorScheme))
        )
    }
}

// MARK: - Escalation Row

private struct EscalationRow: View {
    let entry: EscalationEntry
    let onAcknowledge: () -> Void
    let onResolve: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // Severity badge
                Text(entry.severity.rawValue.uppercased())
                    .font(GasTownTypography.badge)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(severityBadgeColor(entry.severity).opacity(0.15))
                    .foregroundColor(severityBadgeColor(entry.severity))
                    .clipShape(Capsule())

                // Acknowledged indicator
                Text(entry.acknowledged ? "[~]" : "[!]")
                    .font(GasTownTypography.data)
                    .foregroundColor(entry.acknowledged ? GasTownColors.idle : GasTownColors.error)

                // Category
                Text(entry.category.rawValue)
                    .font(GasTownTypography.caption)
                    .foregroundColor(.secondary)

                Spacer()
            }

            // Summary
            Text(entry.summary)
                .font(GasTownTypography.label)
                .lineLimit(2)

            HStack(spacing: 8) {
                // Raised by + age
                Text("\(entry.raisedBy) · \(relativeTime(entry.raisedAt))")
                    .font(GasTownTypography.caption)
                    .foregroundColor(escalationAgeColor(entry))

                Spacer()

                // Action buttons
                if !entry.acknowledged {
                    Button(String(localized: "diagnostics.acknowledge", defaultValue: "Acknowledge")) {
                        onAcknowledge()
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .font(.system(size: 12))
                }

                Button(String(localized: "diagnostics.resolve", defaultValue: "Resolve")) {
                    onResolve()
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .font(.system(size: 12))
            }
        }
        .padding(.horizontal, GasTownSpacing.rowPaddingH)
        .padding(.vertical, GasTownSpacing.rowPaddingV)
    }
}

// MARK: - Shared Sub-Components

/// A SubCheckRow with an inline action button.
private struct ActionSubCheckRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String
    let actionLabel: String
    let isLoading: Bool
    let action: () -> Void

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
            Button(action: action) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(actionLabel)
                }
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .font(.system(size: 12))
            .disabled(isLoading)
        }
        .padding(.horizontal, GasTownSpacing.rowPaddingH)
        .padding(.vertical, GasTownSpacing.rowPaddingV)
    }
}

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

private func severityBadgeColor(_ severity: EscalationSeverity) -> Color {
    switch severity {
    case .critical: return GasTownColors.error
    case .high: return GasTownColors.attention
    case .medium: return GasTownColors.idle
    }
}

private func escalationAgeColor(_ entry: EscalationEntry) -> Color {
    let age = -entry.raisedAt.timeIntervalSinceNow
    if age > 3600 { return GasTownColors.error }
    if age > 1800 { return GasTownColors.attention }
    return .secondary
}

private func formatDuration(_ interval: TimeInterval) -> String {
    if interval < 60 {
        return String(format: "%.0fs", interval)
    }
    if interval < 3600 {
        return String(format: "%.0fm", interval / 60)
    }
    return String(format: "%.1fh", interval / 3600)
}

private func formatDuration(_ interval: TimeInterval?) -> String {
    guard let interval else {
        return String(localized: "diagnostics.unknown", defaultValue: "Unknown")
    }
    return formatDuration(interval)
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

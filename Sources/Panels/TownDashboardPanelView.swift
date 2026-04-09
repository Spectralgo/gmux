import SwiftUI

/// SwiftUI view for the unified Town Dashboard.
/// Renders 4 sections: Agent Roster, Attention, Bead Summary, Activity Feed.
struct TownDashboardPanelView: View {
    @ObservedObject var panel: TownDashboardPanel
    let isFocused: Bool
    let isVisibleInUI: Bool
    let portalPriority: Int
    let onRequestPanelFocus: () -> Void

    @State private var focusFlashOpacity: Double = 0.0
    @State private var focusFlashAnimationGeneration: Int = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            switch panel.loadState {
            case .idle:
                idleView
            case .loading:
                loadingView
            case .loaded(let snapshot):
                dashboardContent(snapshot)
            case .failed(let error):
                errorView(error)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                TownDashboardPointerObserver(onPointerDown: onRequestPanelFocus)
            }
        }
        .onChange(of: panel.focusFlashToken) { _ in
            triggerFocusFlashAnimation()
        }
        .onAppear {
            if case .idle = panel.loadState {
                panel.refresh()
            }
        }
        .onReceive(GasTownService.shared.$refreshTick) { _ in
            switch panel.loadState {
            case .loaded, .failed:
                panel.refresh(silent: true)
            default:
                break
            }
        }
    }

    // MARK: - Dashboard Content

    private func dashboardContent(_ snapshot: TownDashboardSnapshot) -> some View {
        ScrollView {
            VStack(spacing: GasTownSpacing.sectionGap) {
                agentRosterSection(snapshot.agents)
                attentionSection(snapshot.attentionItems)
                beadSummarySection(snapshot.beadCounts)
                activityFeedSection(snapshot.activityFeed)
            }
            .padding(.vertical, GasTownSpacing.cardPadding)
        }
    }

    // MARK: - Agent Roster Section

    private func agentRosterSection(_ agents: [AgentHealthEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                title: String(localized: "dashboard.section.agents", defaultValue: "Agents"),
                icon: "person.3",
                count: agents.count
            )
            Divider().padding(.horizontal, GasTownSpacing.rowPaddingH)

            if agents.isEmpty {
                emptySection(String(
                    localized: "dashboard.agents.empty",
                    defaultValue: "No agents found"
                ))
            } else {
                let grouped = Dictionary(grouping: agents, by: \.rig)
                let rigOrder = orderedRigNames(from: agents)
                LazyVStack(spacing: 0) {
                    ForEach(rigOrder, id: \.self) { rigName in
                        if let rigAgents = grouped[rigName] {
                            rigGroup(rigName, agents: rigAgents)
                        }
                    }
                }
            }
        }
        .background(GasTownColors.sectionBackground(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, GasTownSpacing.rowPaddingH)
    }

    private func rigGroup(_ rigName: String, agents: [AgentHealthEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(rigName)
                .font(GasTownTypography.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, GasTownSpacing.rowPaddingH)
                .padding(.top, 10)
                .padding(.bottom, 4)
            ForEach(agents) { agent in
                agentRow(agent)
                Divider().padding(.horizontal, GasTownSpacing.rowPaddingH)
            }
        }
    }

    private func agentRow(_ agent: AgentHealthEntry) -> some View {
        HStack(spacing: 10) {
            // Role icon
            Image(systemName: GasTownRoleIcon.sfSymbol(for: agent.role))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 16)

            // Status dot
            Circle()
                .fill(agentStatusColor(for: agent))
                .frame(width: GasTownStatusDot.size, height: GasTownStatusDot.size)

            // Name
            Text(agent.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .frame(minWidth: 80, alignment: .leading)

            // Role badge
            Text(agent.role)
                .font(GasTownTypography.badge)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 3))

            Spacer()

            // Work indicator
            if agent.hasWork {
                HStack(spacing: 2) {
                    Image(systemName: "hammer")
                        .font(.system(size: 10))
                    Text(String(localized: "dashboard.agent.working", defaultValue: "working"))
                        .font(GasTownTypography.badge)
                }
                .foregroundColor(.blue)
            }

            // Unread mail
            if agent.unreadMail > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "envelope.badge")
                        .font(.system(size: 10))
                    Text("\(agent.unreadMail)")
                        .font(GasTownTypography.badge)
                }
                .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, GasTownSpacing.rowPaddingH)
        .padding(.vertical, GasTownSpacing.rowPaddingV)
    }

    // MARK: - Attention Section

    private func attentionSection(_ items: [AttentionItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                title: String(localized: "dashboard.section.attention", defaultValue: "Attention"),
                icon: "exclamationmark.triangle",
                count: items.count,
                countColor: items.isEmpty ? nil : GasTownColors.error
            )
            Divider().padding(.horizontal, GasTownSpacing.rowPaddingH)

            if items.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(GasTownColors.active)
                    Text(String(localized: "dashboard.attention.allClear", defaultValue: "All clear"))
                        .font(GasTownTypography.label)
                        .foregroundColor(.secondary)
                }
                .padding(GasTownSpacing.cardPadding)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        attentionRow(item)
                        Divider().padding(.horizontal, GasTownSpacing.rowPaddingH)
                    }
                }
            }
        }
        .background(GasTownColors.sectionBackground(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, GasTownSpacing.rowPaddingH)
    }

    private func attentionRow(_ item: AttentionItem) -> some View {
        HStack(spacing: 8) {
            // Severity icon
            Image(systemName: severityIcon(item.severity))
                .foregroundColor(severityColor(item.severity))
                .font(.system(size: 12))
                .frame(width: 16)

            // Message
            Text(item.message)
                .font(GasTownTypography.label)
                .foregroundColor(.primary)
                .lineLimit(2)

            Spacer()

            // Action button
            if let actionLabel = item.actionLabel {
                Button(actionLabel) {
                    // Action not wired in v1
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .font(.system(size: 11))
            }
        }
        .padding(.horizontal, GasTownSpacing.rowPaddingH)
        .padding(.vertical, GasTownSpacing.rowPaddingV)
    }

    // MARK: - Bead Summary Section

    private func beadSummarySection(_ counts: BeadCountSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                title: String(localized: "dashboard.section.beads", defaultValue: "Beads"),
                icon: "circle.hexagongrid",
                count: nil
            )
            Divider().padding(.horizontal, GasTownSpacing.rowPaddingH)

            HStack(spacing: GasTownSpacing.gridGap) {
                beadCountBadge(
                    count: counts.ready,
                    label: String(localized: "dashboard.beads.ready", defaultValue: "Ready"),
                    color: GasTownColors.active
                )
                beadCountBadge(
                    count: counts.inProgress,
                    label: String(localized: "dashboard.beads.inProgress", defaultValue: "In Progress"),
                    color: GasTownColors.attention
                )
                beadCountBadge(
                    count: counts.closed,
                    label: String(localized: "dashboard.beads.closed", defaultValue: "Closed"),
                    color: GasTownColors.idle
                )
            }
            .padding(GasTownSpacing.cardPadding)
        }
        .background(GasTownColors.sectionBackground(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, GasTownSpacing.rowPaddingH)
    }

    private func beadCountBadge(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(GasTownTypography.sectionHeader)
                .foregroundColor(color)
            Text(label)
                .font(GasTownTypography.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, GasTownSpacing.rowPaddingV)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Activity Feed Section

    private func activityFeedSection(_ entries: [ActivityEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                title: String(localized: "dashboard.section.activity", defaultValue: "Activity"),
                icon: "clock.arrow.circlepath",
                count: nil
            )
            Divider().padding(.horizontal, GasTownSpacing.rowPaddingH)

            if entries.isEmpty {
                emptySection(String(
                    localized: "dashboard.activity.empty",
                    defaultValue: "No recent activity"
                ))
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        activityRow(entry)
                        Divider().padding(.horizontal, GasTownSpacing.rowPaddingH)
                    }
                }
            }
        }
        .background(GasTownColors.sectionBackground(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, GasTownSpacing.rowPaddingH)
    }

    private func activityRow(_ entry: ActivityEntry) -> some View {
        HStack(spacing: 8) {
            // Timestamp
            Text(entry.timestamp)
                .font(GasTownTypography.data)
                .foregroundColor(.secondary)
                .frame(minWidth: 70, alignment: .trailing)

            // Agent icon (if identifiable)
            if let agentName = entry.agentName {
                Image(systemName: "person.circle")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(agentName)
                    .font(GasTownTypography.badge)
                    .foregroundColor(.secondary)
                    .frame(minWidth: 60, alignment: .leading)
            }

            // Message
            Text(entry.message)
                .font(GasTownTypography.label)
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()
        }
        .padding(.horizontal, GasTownSpacing.rowPaddingH)
        .padding(.vertical, 6)
    }

    // MARK: - Shared Components

    private func sectionHeader(title: String, icon: String, count: Int?, countColor: Color? = nil) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .font(.system(size: 12))
            Text(title)
                .font(GasTownTypography.sectionHeader)
                .foregroundColor(.primary)
            if let count {
                Text("(\(count))")
                    .font(GasTownTypography.label)
                    .foregroundColor(countColor ?? .secondary)
            }
            Spacer()
            refreshButton
        }
        .padding(.horizontal, GasTownSpacing.rowPaddingH)
        .padding(.vertical, 10)
    }

    private func emptySection(_ message: String) -> some View {
        Text(message)
            .font(GasTownTypography.caption)
            .foregroundColor(.secondary)
            .padding(GasTownSpacing.cardPadding)
    }

    // MARK: - Idle / Loading / Error States

    private var idleView: some View {
        VStack(spacing: 12) {
            Image(systemName: "building.2")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(String(
                localized: "townDashboard.idle.title",
                defaultValue: "Town Dashboard"
            ))
            .font(.headline)
            .foregroundColor(.primary)
            Text(String(
                localized: "townDashboard.idle.message",
                defaultValue: "Press Refresh to load dashboard data."
            ))
            .font(.caption)
            .foregroundColor(.secondary)
            refreshButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(String(
                localized: "townDashboard.loading",
                defaultValue: "Loading dashboard\u{2026}"
            ))
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: TownDashboardAdapterError) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text(String(
                localized: "townDashboard.error.title",
                defaultValue: "Dashboard Unavailable"
            ))
            .font(.headline)
            .foregroundColor(.primary)
            Text(errorMessage(for: error))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
            refreshButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var refreshButton: some View {
        Button(action: { panel.refresh() }) {
            Label(
                String(localized: "townDashboard.refresh", defaultValue: "Refresh"),
                systemImage: "arrow.clockwise"
            )
            .font(.system(size: 12))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func agentStatusColor(for agent: AgentHealthEntry) -> Color {
        if !agent.isRunning {
            return agent.hasWork ? GasTownColors.error : GasTownColors.idle
        }
        return agent.hasWork ? GasTownColors.attention : GasTownColors.active
    }

    private func severityIcon(_ severity: AttentionSeverity) -> String {
        switch severity {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .critical: return "xmark.circle"
        }
    }

    private func severityColor(_ severity: AttentionSeverity) -> Color {
        switch severity {
        case .info: return GasTownColors.active
        case .warning: return GasTownColors.attention
        case .critical: return GasTownColors.error
        }
    }

    private func orderedRigNames(from entries: [AgentHealthEntry]) -> [String] {
        var seen = Set<String>()
        var order: [String] = []
        for entry in entries {
            if seen.insert(entry.rig).inserted {
                order.append(entry.rig)
            }
        }
        if let townIndex = order.firstIndex(of: "town"), townIndex != 0 {
            order.remove(at: townIndex)
            order.insert("town", at: 0)
        }
        return order
    }

    private func errorMessage(for error: TownDashboardAdapterError) -> String {
        switch error {
        case .cliNotFound(let tool):
            return String(
                localized: "townDashboard.error.cliNotFound",
                defaultValue: "The '\(tool)' CLI was not found on PATH."
            )
        case .cliFailure(let cmd, let code, let stderr):
            return "\(cmd) exited \(code): \(stderr)"
        case .partialFailure(let detail):
            return detail
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

// MARK: - Pointer Observer

private struct TownDashboardPointerObserver: NSViewRepresentable {
    let onPointerDown: () -> Void

    func makeNSView(context: Context) -> TownDashboardPointerObserverView {
        let view = TownDashboardPointerObserverView()
        view.onPointerDown = onPointerDown
        return view
    }

    func updateNSView(_ nsView: TownDashboardPointerObserverView, context: Context) {
        nsView.onPointerDown = onPointerDown
    }
}

final class TownDashboardPointerObserverView: NSView {
    var onPointerDown: (() -> Void)?
    private var eventMonitor: Any?

    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.handleEventIfNeeded(event) ?? event
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard PaneFirstClickFocusSettings.isEnabled(),
              window?.isKeyWindow != true,
              bounds.contains(point) else { return nil }
        return self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        PaneFirstClickFocusSettings.isEnabled()
    }

    override func mouseDown(with event: NSEvent) {
        onPointerDown?()
    }

    private func handleEventIfNeeded(_ event: NSEvent) -> NSEvent {
        guard event.type == .leftMouseDown,
              let window,
              event.window === window,
              !isHiddenOrHasHiddenAncestor else { return event }
        if PaneFirstClickFocusSettings.isEnabled(), window.isKeyWindow != true {
            return event
        }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return event }
        DispatchQueue.main.async { [weak self] in
            self?.onPointerDown?()
        }
        return event
    }
}

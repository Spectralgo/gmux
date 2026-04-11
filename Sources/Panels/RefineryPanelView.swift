import SwiftUI

/// Top-level SwiftUI view for the Refinery Panel.
///
/// Phase 1: basic queue list view with stage badges, bead titles,
/// author, target branch, and elapsed time. No flow bar, no detail
/// expansion, no action buttons.
struct RefineryPanelView: View {
    @ObservedObject var panel: RefineryPanel
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
                pipelineContent(snapshot)
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
                RefineryPanelPointerObserver(onPointerDown: onRequestPanelFocus)
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

    // MARK: - States

    private var idleView: some View {
        Color.clear
    }

    private var loadingView: some View {
        VStack(spacing: GasTownSpacing.gridGap) {
            ProgressView()
            Text(String(localized: "refineryPanel.loading", defaultValue: "Loading merge pipeline..."))
                .font(GasTownTypography.caption)
                .foregroundColor(.secondary)
        }
    }

    private func errorView(_ error: RefineryAdapterError) -> some View {
        VStack(spacing: GasTownSpacing.gridGap) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(GasTownColors.error)
            Text(errorMessage(for: error))
                .font(GasTownTypography.label)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button(String(localized: "refineryPanel.retry", defaultValue: "Retry")) {
                panel.refresh()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
    }

    private func errorMessage(for error: RefineryAdapterError) -> String {
        switch error {
        case .gtCLINotFound:
            return String(localized: "refineryPanel.error.gtNotFound", defaultValue: "Gas Town CLI (gt) not found")
        case .cliFailure(let command, let exitCode, let stderr):
            return String(
                localized: "refineryPanel.error.cliFailed",
                defaultValue: "\(command) failed (exit \(exitCode)): \(stderr.prefix(100))"
            )
        case .parseFailure(_, let detail):
            return String(
                localized: "refineryPanel.error.parseFailed",
                defaultValue: "Failed to parse merge queue data: \(detail.prefix(100))"
            )
        case .refineryNotFound(let rigId):
            return String(
                localized: "refineryPanel.error.refineryNotFound",
                defaultValue: "Refinery not found for rig '\(rigId)'"
            )
        }
    }

    // MARK: - Pipeline Content

    private func pipelineContent(_ snapshot: RefinerySnapshot) -> some View {
        VStack(spacing: 0) {
            pipelineHeader(snapshot)

            Divider()

            if snapshot.queue.isEmpty && snapshot.history.isEmpty {
                emptyQueueView
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Active / building items first
                        let buildingItems = snapshot.queue.filter { $0.stage == .building }
                        if !buildingItems.isEmpty {
                            queueSection(
                                title: String(localized: "refineryPanel.section.active", defaultValue: "Active"),
                                items: buildingItems
                            )
                        }

                        // Waiting items (mergeReady + polecatDone)
                        let waitingItems = snapshot.queue.filter {
                            $0.stage == .mergeReady || $0.stage == .polecatDone
                        }
                        if !waitingItems.isEmpty {
                            queueSection(
                                title: String(localized: "refineryPanel.section.waiting", defaultValue: "Waiting"),
                                items: waitingItems
                            )
                        }

                        // Needs attention (failed + rework)
                        let attentionItems = snapshot.queue.filter {
                            $0.stage == .failed || $0.stage == .rework
                        }
                        if !attentionItems.isEmpty {
                            queueSection(
                                title: String(localized: "refineryPanel.section.attention", defaultValue: "Needs Attention"),
                                items: attentionItems
                            )
                        }

                        // History section
                        if !snapshot.history.isEmpty {
                            historySection(snapshot.history)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Header

    private func pipelineHeader(_ snapshot: RefinerySnapshot) -> some View {
        HStack(spacing: GasTownSpacing.gridGap) {
            Image(systemName: GasTownRoleIcons.refinery)
                .foregroundColor(.secondary)
            Text(String(localized: "refineryPanel.header.title", defaultValue: "Merge Pipeline"))
                .font(GasTownTypography.sectionHeader)
            Spacer()
            RefineryHealthBadge(health: snapshot.health)
            Button {
                panel.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .help(String(localized: "refineryPanel.refresh", defaultValue: "Refresh"))
        }
        .padding(.horizontal, GasTownSpacing.rowPaddingH)
        .padding(.vertical, GasTownSpacing.rowPaddingV)
    }

    // MARK: - Empty State

    private var emptyQueueView: some View {
        VStack(spacing: GasTownSpacing.gridGap) {
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundColor(GasTownColors.active)
            Text(String(localized: "refineryPanel.emptyQueue", defaultValue: "Merge queue is empty"))
                .font(GasTownTypography.label)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Queue Sections

    private func queueSection(title: String, items: [MergeQueueItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(GasTownTypography.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, GasTownSpacing.rowPaddingH)
                .padding(.top, GasTownSpacing.rowPaddingV)
                .padding(.bottom, 4)

            ForEach(items) { item in
                QueueItemCard(item: item)
                if item.id != items.last?.id {
                    Divider()
                        .padding(.leading, GasTownSpacing.rowPaddingH)
                }
            }
        }
    }

    private func historySection(_ entries: [MergeHistoryEntry]) -> some View {
        DisclosureGroup {
            ForEach(entries) { entry in
                HistoryEntryRow(entry: entry)
                if entry.id != entries.last?.id {
                    Divider()
                        .padding(.leading, GasTownSpacing.rowPaddingH)
                }
            }
        } label: {
            Text(String(
                localized: "refineryPanel.section.history",
                defaultValue: "Recent Merges (\(entries.count))"
            ))
            .font(GasTownTypography.caption)
            .foregroundColor(.secondary)
            .textCase(.uppercase)
        }
        .padding(.horizontal, GasTownSpacing.rowPaddingH)
        .padding(.top, GasTownSpacing.rowPaddingV)
    }

    // MARK: - Focus Flash Animation

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

// MARK: - Queue Item Card

private struct QueueItemCard: View {
    let item: MergeQueueItem

    var body: some View {
        HStack(spacing: GasTownSpacing.gridGap) {
            StageBadge(stage: item.stage)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.id)
                        .font(GasTownTypography.data)
                        .foregroundColor(.secondary)
                    Text(item.title)
                        .font(GasTownTypography.label)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Text(item.author)
                        .font(GasTownTypography.caption)
                        .foregroundColor(.secondary)
                    Text("\u{2192}")
                        .font(GasTownTypography.caption)
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(item.targetBranch)
                        .font(GasTownTypography.data)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(elapsedTime(since: item.enteredStageAt))
                        .font(GasTownTypography.caption)
                        .foregroundColor(.secondary)
                }

                if item.stage == .failed, let errorSummary = item.errorSummary {
                    Text(errorSummary)
                        .font(GasTownTypography.caption)
                        .foregroundColor(GasTownColors.error)
                        .lineLimit(1)
                }

                if item.stage == .rework, let reworkPolecat = item.reworkPolecat {
                    Text(String(
                        localized: "refineryPanel.reworkBy",
                        defaultValue: "Rework by: \(reworkPolecat)"
                    ))
                    .font(GasTownTypography.caption)
                    .foregroundColor(.purple)
                    .lineLimit(1)
                }
            }

            if item.stage == .building, let progress = item.buildProgress {
                ProgressView(value: progress)
                    .frame(width: 60)
            }
        }
        .padding(.horizontal, GasTownSpacing.rowPaddingH)
        .padding(.vertical, GasTownSpacing.rowPaddingV)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(
            "\(item.title), by \(item.author), stage \(item.stage.rawValue)"
        ))
    }

    private func elapsedTime(since date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return String(localized: "refineryPanel.elapsed.now", defaultValue: "just now")
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

// MARK: - Stage Badge

private struct StageBadge: View {
    let stage: MergePipelineStage

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: stageIcon)
                .font(.system(size: 9))
            Text(stageLabel)
                .font(GasTownTypography.badge)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(stageColor.opacity(0.15))
        .foregroundColor(stageColor)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityLabel(Text(stageLabel))
    }

    private var stageColor: Color {
        switch stage {
        case .polecatDone: return GasTownColors.idle
        case .mergeReady: return cmuxAccentColor()
        case .building: return GasTownColors.attention
        case .merged: return GasTownColors.active
        case .failed: return GasTownColors.error
        case .rework: return .purple
        case .skipped: return GasTownColors.idle.opacity(0.5)
        }
    }

    private var stageIcon: String {
        switch stage {
        case .polecatDone: return "clock"
        case .mergeReady: return "checkmark.shield"
        case .building: return "hammer"
        case .merged: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .rework: return "arrow.triangle.2.circlepath"
        case .skipped: return "forward.end"
        }
    }

    private var stageLabel: String {
        switch stage {
        case .polecatDone:
            return String(localized: "refineryPanel.stage.polecatDone", defaultValue: "Queued")
        case .mergeReady:
            return String(localized: "refineryPanel.stage.mergeReady", defaultValue: "Ready")
        case .building:
            return String(localized: "refineryPanel.stage.building", defaultValue: "Building")
        case .merged:
            return String(localized: "refineryPanel.stage.merged", defaultValue: "Merged")
        case .failed:
            return String(localized: "refineryPanel.stage.failed", defaultValue: "Failed")
        case .rework:
            return String(localized: "refineryPanel.stage.rework", defaultValue: "Rework")
        case .skipped:
            return String(localized: "refineryPanel.stage.skipped", defaultValue: "Skipped")
        }
    }
}

// MARK: - Refinery Health Badge

private struct RefineryHealthBadge: View {
    let health: RefineryHealth

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(healthColor)
                .frame(width: GasTownStatusDot.size, height: GasTownStatusDot.size)
            Text(healthLabel)
                .font(GasTownTypography.caption)
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(String(
            localized: "refineryPanel.health.label",
            defaultValue: "Refinery status: \(healthLabel)"
        )))
    }

    private var healthColor: Color {
        switch health {
        case .patrol: return GasTownColors.active
        case .processing: return GasTownColors.attention
        case .idle: return GasTownColors.idle
        case .error: return GasTownColors.error
        }
    }

    private var healthLabel: String {
        switch health {
        case .patrol:
            return String(localized: "refineryPanel.health.patrol", defaultValue: "Patrol")
        case .processing:
            return String(localized: "refineryPanel.health.processing", defaultValue: "Processing")
        case .idle:
            return String(localized: "refineryPanel.health.idle", defaultValue: "Idle")
        case .error:
            return String(localized: "refineryPanel.health.error", defaultValue: "Error")
        }
    }
}

// MARK: - History Entry Row

private struct HistoryEntryRow: View {
    let entry: MergeHistoryEntry

    var body: some View {
        HStack(spacing: GasTownSpacing.gridGap) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(GasTownColors.active)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.id)
                        .font(GasTownTypography.data)
                        .foregroundColor(.secondary)
                    Text(entry.title)
                        .font(GasTownTypography.label)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    Text(entry.author)
                        .font(GasTownTypography.caption)
                        .foregroundColor(.secondary)
                    if let beadId = entry.beadId {
                        Text(beadId)
                            .font(GasTownTypography.data)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, GasTownSpacing.rowPaddingH)
        .padding(.vertical, GasTownSpacing.rowPaddingV)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(entry.title), merged by \(entry.author)"))
    }
}

// MARK: - Pointer Observer

private struct RefineryPanelPointerObserver: NSViewRepresentable {
    let onPointerDown: () -> Void

    func makeNSView(context: Context) -> RefineryPanelPointerObserverView {
        let view = RefineryPanelPointerObserverView()
        view.onPointerDown = onPointerDown
        return view
    }

    func updateNSView(_ nsView: RefineryPanelPointerObserverView, context: Context) {
        nsView.onPointerDown = onPointerDown
    }
}

final class RefineryPanelPointerObserverView: NSView {
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

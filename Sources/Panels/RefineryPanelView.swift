import SwiftUI

/// Top-level SwiftUI view for the Refinery Panel.
///
/// Phase 3: Action buttons (merge, retry, skip, force-merge, merge-all),
/// rig selector, cross-panel links, keyboard navigation, and full
/// accessibility (VoiceOver labels, hints, traits).
struct RefineryPanelView: View {
    @ObservedObject var panel: RefineryPanel
    let isFocused: Bool
    let isVisibleInUI: Bool
    let portalPriority: Int
    let onRequestPanelFocus: () -> Void

    @State private var focusFlashOpacity: Double = 0.0
    @State private var focusFlashAnimationGeneration: Int = 0
    @State private var showMergeAllConfirmation: Bool = false
    @State private var showForceMergeConfirmation: String? = nil
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
        .overlay(alignment: .top) {
            actionResultBanner
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
        .background(
            RefineryKeyHandler(panel: panel, showMergeAllConfirmation: $showMergeAllConfirmation)
        )
        .confirmationDialog(
            String(localized: "refineryPanel.mergeAll.confirm.title",
                   defaultValue: "Merge All Passed Items?"),
            isPresented: $showMergeAllConfirmation
        ) {
            Button(String(localized: "refineryPanel.mergeAll.confirm.action",
                          defaultValue: "Merge All")) {
                panel.mergeAllPassed()
            }
            Button(String(localized: "refineryPanel.cancel", defaultValue: "Cancel"),
                   role: .cancel) {}
        }
        .confirmationDialog(
            String(localized: "refineryPanel.forceMerge.confirm.title",
                   defaultValue: "Force Merge Without Passing Build?"),
            isPresented: Binding(
                get: { showForceMergeConfirmation != nil },
                set: { if !$0 { showForceMergeConfirmation = nil } }
            )
        ) {
            if let itemId = showForceMergeConfirmation {
                Button(String(localized: "refineryPanel.forceMerge.confirm.action",
                              defaultValue: "Force Merge"), role: .destructive) {
                    panel.forceMergeItem(itemId)
                }
            }
            Button(String(localized: "refineryPanel.cancel", defaultValue: "Cancel"),
                   role: .cancel) {}
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
            HStack(spacing: GasTownSpacing.gridGap) {
                Button(String(localized: "refineryPanel.retry", defaultValue: "Retry")) {
                    panel.refresh()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(String(localized: "refineryPanel.openDiagnostics", defaultValue: "Open Diagnostics")) {
                    NotificationCenter.default.post(
                        name: .openDiagnosticsPanel,
                        object: nil,
                        userInfo: ["workspaceId": panel.workspaceId]
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
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

    // MARK: - Action Result Banner

    @ViewBuilder
    private var actionResultBanner: some View {
        if let result = panel.actionResult {
            HStack(spacing: GasTownSpacing.gridGap) {
                switch result {
                case .success(let message):
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(GasTownColors.active)
                    Text(message)
                        .font(GasTownTypography.caption)
                case .failure(let message):
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(GasTownColors.error)
                    Text(message)
                        .font(GasTownTypography.caption)
                }
            }
            .padding(.horizontal, GasTownSpacing.rowPaddingH)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.top, GasTownSpacing.rowPaddingV)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Pipeline Content

    private func pipelineContent(_ snapshot: RefinerySnapshot) -> some View {
        VStack(spacing: 0) {
            pipelineHeader(snapshot)

            Divider()

            PipelineFlowBar(stageCounts: snapshot.stageCounts)
                .padding(.horizontal, GasTownSpacing.rowPaddingH)
                .padding(.vertical, GasTownSpacing.rowPaddingV)

            Divider()

            if snapshot.queue.isEmpty && snapshot.skipped.isEmpty && snapshot.history.isEmpty {
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

                        // Skipped section (collapsed by default)
                        if !snapshot.skipped.isEmpty {
                            skippedSection(snapshot.skipped)
                        }

                        // History section (collapsed by default)
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
        VStack(spacing: 4) {
            HStack(spacing: GasTownSpacing.gridGap) {
                Image(systemName: GasTownRoleIcons.refinery)
                    .foregroundColor(.secondary)
                Text(String(localized: "refineryPanel.header.title", defaultValue: "Merge Pipeline"))
                    .font(GasTownTypography.sectionHeader)

                RigSelectorPicker(
                    selectedRigId: panel.rigId,
                    onSelect: { panel.switchRig($0) }
                )

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

            // Merge All Passed button (shows only when there are passed items)
            if snapshot.passedCount > 0 {
                MergeAllPassedButton(
                    passedCount: snapshot.passedCount,
                    action: { showMergeAllConfirmation = true }
                )
            }
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
                VStack(spacing: 0) {
                    QueueItemCard(
                        item: item,
                        isExpanded: panel.selectedItemId == item.id,
                        onTap: {
                            if panel.selectedItemId == item.id {
                                panel.collapseItem()
                            } else {
                                panel.expandItem(item.id)
                            }
                        },
                        onMerge: { panel.mergeItem(item.id) },
                        onRetry: { panel.retryItem(item.id) },
                        onSkip: { panel.skipItem(item.id) }
                    )

                    if panel.selectedItemId == item.id {
                        QueueItemDetail(
                            item: item,
                            buildLogState: panel.buildLogState,
                            workspaceId: panel.workspaceId,
                            rigId: panel.rigId,
                            onRetry: { panel.retryItem(item.id) },
                            onRetryClean: { panel.retryItem(item.id, clean: true) },
                            onSkip: { panel.skipItem(item.id) },
                            onForceMerge: { showForceMergeConfirmation = item.id },
                            onMerge: { panel.mergeItem(item.id) }
                        )
                        .transition(.opacity)
                    }
                }

                if item.id != items.last?.id {
                    Divider()
                        .padding(.leading, GasTownSpacing.rowPaddingH)
                }
            }
        }
    }

    // MARK: - Skipped Section

    private func skippedSection(_ items: [MergeQueueItem]) -> some View {
        DisclosureGroup {
            ForEach(items) { item in
                SkippedItemRow(item: item)
                if item.id != items.last?.id {
                    Divider()
                        .padding(.leading, GasTownSpacing.rowPaddingH)
                }
            }
        } label: {
            Text(String(
                localized: "refineryPanel.section.skipped",
                defaultValue: "Skipped (\(items.count))"
            ))
            .font(GasTownTypography.caption)
            .foregroundColor(.secondary)
            .textCase(.uppercase)
        }
        .padding(.horizontal, GasTownSpacing.rowPaddingH)
        .padding(.top, GasTownSpacing.rowPaddingV)
        .accessibilityElement(children: .contain)
    }

    private func historySection(_ entries: [MergeHistoryEntry]) -> some View {
        DisclosureGroup {
            ForEach(entries) { entry in
                HistoryEntryRow(entry: entry, workspaceId: panel.workspaceId)
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
        .accessibilityElement(children: .contain)
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

// MARK: - Keyboard Handler

/// AppKit NSView-based key handler for Refinery Panel keyboard navigation.
///
/// Intercepts arrow keys, Return, M, R, S, Shift+M, Escape when the panel
/// has focus. Does not interfere with terminal input — only active when
/// the Refinery Panel is focused.
private struct RefineryKeyHandler: NSViewRepresentable {
    let panel: RefineryPanel
    @Binding var showMergeAllConfirmation: Bool

    func makeNSView(context: Context) -> RefineryKeyHandlerView {
        let view = RefineryKeyHandlerView()
        view.panel = panel
        view.showMergeAllConfirmation = { showMergeAllConfirmation = true }
        return view
    }

    func updateNSView(_ nsView: RefineryKeyHandlerView, context: Context) {
        nsView.panel = panel
        nsView.showMergeAllConfirmation = { showMergeAllConfirmation = true }
    }
}

final class RefineryKeyHandlerView: NSView {
    var panel: RefineryPanel?
    var showMergeAllConfirmation: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let panel else {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 125: // Down arrow
            panel.selectNextItem()
        case 126: // Up arrow
            panel.selectPreviousItem()
        case 36: // Return
            if panel.selectedItemId != nil {
                // Toggle expand: if already expanded, collapse
                panel.collapseItem()
            } else {
                panel.selectNextItem()
            }
        case 53: // Escape
            if panel.selectedItemId != nil {
                panel.collapseItem()
            }
        default:
            if let chars = event.characters {
                if event.modifierFlags.contains(.shift) && chars.lowercased() == "m" {
                    showMergeAllConfirmation?()
                } else if let char = chars.first {
                    panel.handleKeyAction(char)
                }
            }
        }
    }
}

// MARK: - Pipeline Flow Bar

/// Horizontal flow visualization showing stage indicators with arrows and counts.
private struct PipelineFlowBar: View {
    let stageCounts: PipelineStageCounts

    private let stages: [(stage: MergePipelineStage, label: String, icon: String)] = [
        (.polecatDone, String(localized: "refineryPanel.flow.polecatDone", defaultValue: "Queued"), "clock"),
        (.mergeReady, String(localized: "refineryPanel.flow.mergeReady", defaultValue: "Ready"), "checkmark.shield"),
        (.building, String(localized: "refineryPanel.flow.building", defaultValue: "Building"), "hammer"),
        (.merged, String(localized: "refineryPanel.flow.merged", defaultValue: "Merged"), "checkmark.circle.fill"),
        (.failed, String(localized: "refineryPanel.flow.failed", defaultValue: "Failed"), "xmark.circle.fill"),
        (.rework, String(localized: "refineryPanel.flow.rework", defaultValue: "Rework"), "arrow.triangle.2.circlepath"),
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(stages.enumerated()), id: \.offset) { index, stageInfo in
                FlowStageIndicator(
                    stage: stageInfo.stage,
                    label: stageInfo.label,
                    icon: stageInfo.icon,
                    count: count(for: stageInfo.stage)
                )

                // Arrow between linear stages (not after merged/failed/rework)
                if index < 3 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.4))
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func count(for stage: MergePipelineStage) -> Int {
        switch stage {
        case .polecatDone: return stageCounts.polecatDone
        case .mergeReady: return stageCounts.mergeReady
        case .building: return stageCounts.building
        case .merged: return stageCounts.merged
        case .failed: return stageCounts.failed
        case .rework: return stageCounts.rework
        case .skipped: return 0
        }
    }
}

/// Single stage indicator in the flow bar.
private struct FlowStageIndicator: View {
    let stage: MergePipelineStage
    let label: String
    let icon: String
    let count: Int

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(stageColor.opacity(count > 0 ? 1.0 : 0.2))
                    .frame(width: 12, height: 12)

                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            Text(label)
                .font(GasTownTypography.caption)
                .foregroundColor(count > 0 ? stageColor : .secondary.opacity(0.5))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(String(
            localized: "refineryPanel.flow.stageLabel",
            defaultValue: "\(label): \(count) items"
        )))
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
}

// MARK: - Queue Item Card

/// Compact row for a queue item with expand/collapse support and inline action buttons.
///
/// Uses `Equatable` conformance for view efficiency — body is only
/// re-evaluated when the item or expansion state actually changes.
private struct QueueItemCard: View, Equatable {
    let item: MergeQueueItem
    let isExpanded: Bool
    let onTap: () -> Void
    let onMerge: () -> Void
    let onRetry: () -> Void
    let onSkip: () -> Void

    @State private var isHovering: Bool = false

    static func == (lhs: QueueItemCard, rhs: QueueItemCard) -> Bool {
        lhs.item == rhs.item && lhs.isExpanded == rhs.isExpanded
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: GasTownSpacing.gridGap) {
                StageBadge(stage: item.stage)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        BeadIdLink(beadId: item.id)
                        Text(item.title)
                            .font(GasTownTypography.label)
                            .lineLimit(1)
                    }

                    HStack(spacing: 4) {
                        AgentNameLink(
                            name: item.author,
                            agentAddress: item.author
                        )
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

                // Inline action buttons (visible on hover)
                if isHovering && !isExpanded {
                    inlineActionButtons
                }

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, GasTownSpacing.rowPaddingH)
            .padding(.vertical, GasTownSpacing.rowPaddingV)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(
            "\(item.title), by \(item.author), stage \(item.stage.rawValue)"
        ))
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var inlineActionButtons: some View {
        HStack(spacing: 4) {
            if item.stage == .mergeReady {
                Button {
                    onMerge()
                } label: {
                    Text(String(localized: "refineryPanel.action.merge", defaultValue: "Merge"))
                        .font(GasTownTypography.badge)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(GasTownColors.active)
                .accessibilityLabel(Text(String(
                    localized: "refineryPanel.action.merge.label",
                    defaultValue: "Merge \(item.id)"
                )))
            }

            if item.stage == .failed {
                Button {
                    onRetry()
                } label: {
                    Text(String(localized: "refineryPanel.action.retry", defaultValue: "Retry"))
                        .font(GasTownTypography.badge)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .accessibilityLabel(Text(String(
                    localized: "refineryPanel.action.retry.label",
                    defaultValue: "Retry build for \(item.id)"
                )))

                Button {
                    onSkip()
                } label: {
                    Text(String(localized: "refineryPanel.action.skip", defaultValue: "Skip"))
                        .font(GasTownTypography.badge)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .accessibilityLabel(Text(String(
                    localized: "refineryPanel.action.skip.label",
                    defaultValue: "Skip \(item.id)"
                )))
            }
        }
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

// MARK: - Bead ID Link

/// Clickable bead ID that opens the Bead Inspector.
private struct BeadIdLink: View {
    let beadId: String

    var body: some View {
        Button {
            NotificationCenter.default.post(
                name: .openBeadInspector,
                object: nil,
                userInfo: ["beadId": beadId]
            )
        } label: {
            Text(beadId)
                .font(GasTownTypography.data)
                .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Queue Item Detail

/// Expanded detail view below a selected queue item card.
///
/// Shows error summary, build log viewer (for failed items), rework info,
/// file change information, and action buttons row with cross-panel links.
private struct QueueItemDetail: View {
    let item: MergeQueueItem
    let buildLogState: BuildLogLoadState
    let workspaceId: UUID
    let rigId: String
    let onRetry: () -> Void
    let onRetryClean: () -> Void
    let onSkip: () -> Void
    let onForceMerge: () -> Void
    let onMerge: () -> Void

    @State private var showErrorsOnly: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: GasTownSpacing.gridGap) {
            // Failed item detail
            if item.stage == .failed {
                failedDetail
            }

            // Rework item detail
            if item.stage == .rework {
                reworkDetail
            }

            // Branch info
            HStack(spacing: 4) {
                Text(String(localized: "refineryPanel.detail.branch", defaultValue: "Branch:"))
                    .font(GasTownTypography.caption)
                    .foregroundColor(.secondary)
                Text(item.sourceBranch)
                    .font(GasTownTypography.data)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            if item.fileCount > 0 {
                Text(String(
                    localized: "refineryPanel.detail.fileCount",
                    defaultValue: "\(item.fileCount) files changed"
                ))
                .font(GasTownTypography.caption)
                .foregroundColor(.secondary)
            }

            Divider()

            // Action buttons row
            actionButtonsRow
        }
        .padding(.horizontal, GasTownSpacing.rowPaddingH)
        .padding(.vertical, GasTownSpacing.rowPaddingV)
        .background(Color.secondary.opacity(0.05))
    }

    // MARK: - Action Buttons Row

    private var actionButtonsRow: some View {
        HStack(spacing: GasTownSpacing.gridGap) {
            if item.stage == .mergeReady {
                Button {
                    onMerge()
                } label: {
                    Label(
                        String(localized: "refineryPanel.detail.merge", defaultValue: "Merge"),
                        systemImage: "checkmark.circle"
                    )
                    .font(GasTownTypography.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(GasTownColors.active)
                .accessibilityLabel(Text(String(
                    localized: "refineryPanel.detail.merge.label",
                    defaultValue: "Merge \(item.id)"
                )))
            }

            if item.stage == .failed || item.stage == .rework {
                Button {
                    onRetry()
                } label: {
                    Label(
                        String(localized: "refineryPanel.detail.retry", defaultValue: "Retry"),
                        systemImage: "arrow.counterclockwise"
                    )
                    .font(GasTownTypography.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(Text(String(
                    localized: "refineryPanel.detail.retry.label",
                    defaultValue: "Retry build for \(item.id)"
                )))

                Button {
                    onRetryClean()
                } label: {
                    Label(
                        String(localized: "refineryPanel.detail.retryClean", defaultValue: "Retry Clean"),
                        systemImage: "arrow.counterclockwise.circle"
                    )
                    .font(GasTownTypography.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(Text(String(
                    localized: "refineryPanel.detail.retryClean.label",
                    defaultValue: "Retry clean build for \(item.id)"
                )))

                Button {
                    onSkip()
                } label: {
                    Label(
                        String(localized: "refineryPanel.detail.skip", defaultValue: "Skip"),
                        systemImage: "forward.end"
                    )
                    .font(GasTownTypography.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(Text(String(
                    localized: "refineryPanel.detail.skip.label",
                    defaultValue: "Skip \(item.id)"
                )))
            }

            if item.stage == .failed {
                Button(role: .destructive) {
                    onForceMerge()
                } label: {
                    Label(
                        String(localized: "refineryPanel.detail.forceMerge", defaultValue: "Force Merge"),
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(GasTownTypography.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(Text(String(
                    localized: "refineryPanel.detail.forceMerge.label",
                    defaultValue: "Force merge \(item.id) without passing build"
                )))
                .accessibilityHint(Text(String(
                    localized: "refineryPanel.detail.forceMerge.hint",
                    defaultValue: "Merges without a passing build. Use with caution."
                )))
            }

            Spacer()

            // Cross-panel link buttons
            Button {
                NotificationCenter.default.post(
                    name: .openDiffPanel,
                    object: nil,
                    userInfo: ["commitSha": item.sourceBranch, "workspaceId": workspaceId]
                )
            } label: {
                Label(
                    String(localized: "refineryPanel.detail.viewDiff", defaultValue: "View Diff"),
                    systemImage: "doc.text.magnifyingglass"
                )
                .font(GasTownTypography.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                NotificationCenter.default.post(
                    name: .openTerminalAttach,
                    object: nil,
                    userInfo: [
                        "sessionName": "refinery-\(rigId)",
                        "workspaceId": workspaceId,
                    ]
                )
            } label: {
                Label(
                    String(localized: "refineryPanel.detail.openTerminal", defaultValue: "Open in Terminal"),
                    systemImage: "terminal"
                )
                .font(GasTownTypography.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Failed Detail

    @ViewBuilder
    private var failedDetail: some View {
        if let errorSummary = item.errorSummary {
            Text(errorSummary)
                .font(GasTownTypography.label)
                .foregroundColor(GasTownColors.error)
        }

        buildLogViewer
    }

    @ViewBuilder
    private var buildLogViewer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(String(localized: "refineryPanel.detail.buildLog", defaultValue: "Build Log"))
                    .font(GasTownTypography.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()

                if case .loaded = buildLogState {
                    Toggle(isOn: $showErrorsOnly) {
                        Text(String(
                            localized: "refineryPanel.detail.errorsOnly",
                            defaultValue: "Errors Only"
                        ))
                        .font(GasTownTypography.caption)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
            }

            switch buildLogState {
            case .idle:
                EmptyView()
            case .loading:
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "refineryPanel.detail.loadingLog", defaultValue: "Loading build log..."))
                        .font(GasTownTypography.caption)
                        .foregroundColor(.secondary)
                }
            case .loaded(let log):
                buildLogContent(log)
            case .failed(let error):
                Text(String(
                    localized: "refineryPanel.detail.logFailed",
                    defaultValue: "Failed to load build log: \(error.localizedDescription)"
                ))
                .font(GasTownTypography.caption)
                .foregroundColor(GasTownColors.error)
            }
        }
    }

    private func buildLogContent(_ log: String) -> some View {
        let displayLog = showErrorsOnly ? filterErrorLines(log) : log
        return ScrollView(.vertical) {
            Text(displayLog)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(GasTownSpacing.gridGap)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityAddTraits(.allowsDirectInteraction)
        }
        .frame(maxHeight: 300)
        .background(Color.black.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityLabel(Text(String(
            localized: "refineryPanel.detail.buildLogLabel",
            defaultValue: "Build log for \(item.id), \(log.components(separatedBy: .newlines).count) lines"
        )))
    }

    private func filterErrorLines(_ log: String) -> String {
        let errorPatterns = ["error", "Error", "ERROR", "FAIL", "failed", "fatal"]
        let lines = log.components(separatedBy: .newlines)
        let filtered = lines.filter { line in
            errorPatterns.contains(where: { line.contains($0) })
        }
        return filtered.isEmpty
            ? String(localized: "refineryPanel.detail.noErrors", defaultValue: "No error lines found")
            : filtered.joined(separator: "\n")
    }

    // MARK: - Rework Detail

    @ViewBuilder
    private var reworkDetail: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(
                localized: "refineryPanel.detail.submittedBy",
                defaultValue: "Originally submitted by: \(item.author)"
            ))
            .font(GasTownTypography.caption)
            .foregroundColor(.secondary)

            if let reworkPolecat = item.reworkPolecat {
                HStack(spacing: 4) {
                    Text(String(
                        localized: "refineryPanel.detail.conflictResolution",
                        defaultValue: "Conflict resolution by:"
                    ))
                    .font(GasTownTypography.caption)
                    .foregroundColor(.purple)

                    AgentNameLink(
                        name: reworkPolecat,
                        agentAddress: reworkPolecat
                    )
                    .accessibilityHint(Text(String(
                        localized: "refineryPanel.detail.viewAgent.hint",
                        defaultValue: "Opens the agent profile for the polecat resolving this conflict."
                    )))
                }

                if let conflictCount = item.conflictFileCount {
                    Text(String(
                        localized: "refineryPanel.detail.conflictFiles",
                        defaultValue: "\(conflictCount) files in conflict"
                    ))
                    .font(GasTownTypography.caption)
                    .foregroundColor(GasTownColors.attention)
                }
            }
        }
        .accessibilityLabel(Text(String(
            localized: "refineryPanel.detail.reworkLabel",
            defaultValue: "\(item.id) has conflicts, being resolved by \(item.reworkPolecat ?? "unknown")"
        )))
    }
}

// MARK: - Merge All Passed Button

/// Button to merge all items with passing builds, shown in the header.
private struct MergeAllPassedButton: View {
    let passedCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                Text(String(
                    localized: "refineryPanel.mergeAll.button",
                    defaultValue: "Merge All Passed (\(passedCount))"
                ))
                .font(GasTownTypography.caption)
            }
            .padding(.horizontal, GasTownSpacing.gridGap)
            .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(GasTownColors.active)
        .accessibilityLabel(Text(String(
            localized: "refineryPanel.mergeAll.label",
            defaultValue: "Merge all \(passedCount) passed items"
        )))
    }
}

// MARK: - Rig Selector Picker

/// Picker that lets the operator switch which rig's refinery is displayed.
private struct RigSelectorPicker: View {
    let selectedRigId: String
    let onSelect: (String) -> Void

    @ObservedObject private var gasTownService = GasTownService.shared

    var body: some View {
        if gasTownService.rigs.count > 1 {
            Picker(selection: Binding(
                get: { selectedRigId },
                set: { onSelect($0) }
            )) {
                ForEach(gasTownService.rigs) { rig in
                    Text(rig.name)
                        .tag(rig.id)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 120)
            .accessibilityLabel(Text(String(
                localized: "refineryPanel.rigSelector.label",
                defaultValue: "Select rig, currently \(selectedRigId)"
            )))
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

// MARK: - Skipped Item Row

private struct SkippedItemRow: View {
    let item: MergeQueueItem

    var body: some View {
        HStack(spacing: GasTownSpacing.gridGap) {
            Image(systemName: "forward.end")
                .font(.system(size: 10))
                .foregroundColor(GasTownColors.idle.opacity(0.5))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    BeadIdLink(beadId: item.id)
                    Text(item.title)
                        .font(GasTownTypography.label)
                        .foregroundColor(.secondary.opacity(0.6))
                        .lineLimit(1)
                }
                AgentNameLink(
                    name: item.author,
                    agentAddress: item.author
                )
            }

            Spacer()
        }
        .padding(.horizontal, GasTownSpacing.rowPaddingH)
        .padding(.vertical, GasTownSpacing.rowPaddingV)
    }
}

// MARK: - History Entry Row

private struct HistoryEntryRow: View {
    let entry: MergeHistoryEntry
    let workspaceId: UUID

    var body: some View {
        HStack(spacing: GasTownSpacing.gridGap) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(GasTownColors.active)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    // Commit SHA as clickable link to diff panel
                    Button {
                        NotificationCenter.default.post(
                            name: .openDiffPanel,
                            object: nil,
                            userInfo: ["commitSha": entry.id, "workspaceId": workspaceId]
                        )
                    } label: {
                        Text(entry.id)
                            .font(GasTownTypography.data)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }

                    Text(entry.title)
                        .font(GasTownTypography.label)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    AgentNameLink(
                        name: entry.author,
                        agentAddress: entry.author
                    )
                    if let beadId = entry.beadId {
                        BeadIdLink(beadId: beadId)
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

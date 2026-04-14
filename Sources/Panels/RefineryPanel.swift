import Foundation
import SwiftUI
import Combine

/// Panel showing the merge pipeline queue for a rig's refinery.
///
/// Phase 2: Real-time socket events, expand/collapse detail, build log
/// lazy loading, hybrid refresh strategy, and PipelineFlowBar.
///
/// Follows the same load/refresh pattern as ``RigPanel``:
/// - Initial load on `.onAppear`
/// - Auto-refresh via `GasTownService.shared.$refreshTick` (8s)
/// - Silent refresh skips `.loading` state and only publishes on change
///
/// Phase 2 additions:
/// - Observes ``MailInboxStore`` for pipeline events (POLECAT_DONE, etc.)
/// - Immediate stage transitions on socket events, polling as fallback
/// - Build log lazy loading with 50k char truncation and in-memory cache
/// - Expand/collapse queue items with detail view
@MainActor
final class RefineryPanel: Panel, ObservableObject {
    let id: UUID
    let panelType: PanelType = .refinery

    @Published private(set) var displayTitle: String = String(
        localized: "refineryPanel.title",
        defaultValue: "Merge Pipeline"
    )
    @Published private(set) var loadState: RefineryLoadState = .idle

    /// Currently selected queue item for expanded detail view.
    @Published var selectedItemId: String?

    /// Build log loading state for the expanded item.
    @Published private(set) var buildLogState: BuildLogLoadState = .idle

    /// Action result banner (auto-dismisses after 4s).
    @Published var actionResult: RefineryActionResult?

    /// Token incremented to trigger focus flash animation.
    @Published private(set) var focusFlashToken: Int = 0

    var displayIcon: String? { GasTownRoleIcons.refinery }

    /// The rig this panel displays. Mutable for rig selector switching.
    var rigId: String

    /// Workspace that owns this panel.
    let workspaceId: UUID

    /// Data adapter for loading refinery data.
    private let adapter: RefineryAdapter

    /// Tick counter for refresh cadence.
    private var tickCounter: Int = 0

    /// Build log cache: itemId → log text. Cleared on refresh.
    private var buildLogCache: [String: String] = [:]

    /// Cancellables for Combine subscriptions.
    private var cancellables = Set<AnyCancellable>()

    /// Last processed mail message count, for incremental event processing.
    private var lastMailCount: Int = 0

    init(rigId: String, workspaceId: UUID, adapter: RefineryAdapter) {
        self.id = UUID()
        self.rigId = rigId
        self.workspaceId = workspaceId
        self.adapter = adapter

        subscribeToMailEvents()
    }

    // MARK: - Panel protocol

    func focus() {}
    func unfocus() {}
    func close() {}

    func triggerFlash(reason: WorkspaceAttentionFlashReason) {
        _ = reason
        guard NotificationPaneFlashSettings.isEnabled() else { return }
        focusFlashToken += 1
    }

    // MARK: - Data Loading

    /// Load refinery data. Runs CLI calls off-main, publishes on main.
    ///
    /// - Parameter silent: When `true` (auto-refresh), skips `.loading` state
    ///   and only publishes if data changed.
    func refresh(silent: Bool = false) {
        if !silent {
            loadState = .loading
        }

        let adapter = self.adapter
        let rigId = self.rigId

        if silent {
            tickCounter += 1
        } else {
            tickCounter = 0
            // Clear build log cache on manual refresh (logs may change after retry)
            buildLogCache.removeAll()
        }

        Task {
            let result = await adapter.loadSnapshot(rigId: rigId)
            switch result {
            case .success(let snapshot):
                let newState = RefineryLoadState.loaded(snapshot)
                if self.loadState != newState {
                    self.loadState = newState
                }
            case .failure(let error):
                let newState = RefineryLoadState.failed(error)
                if self.loadState != newState {
                    self.loadState = newState
                }
            }
        }
    }

    // MARK: - Rig Switching

    /// Switch to a different rig, clearing all state and refreshing.
    func switchRig(_ newRigId: String) {
        rigId = newRigId
        selectedItemId = nil
        buildLogCache.removeAll()
        buildLogState = .idle
        actionResult = nil
        loadState = .loading
        refresh()
    }

    // MARK: - Detail Expansion

    /// Expand a queue item to show its detail view.
    func expandItem(_ itemId: String) {
        selectedItemId = itemId
        loadBuildLog(for: itemId)
    }

    /// Collapse the currently expanded item.
    func collapseItem() {
        selectedItemId = nil
        buildLogState = .idle
    }

    // MARK: - Build Log Loading

    /// Lazy-load build log for a queue item.
    ///
    /// Uses in-memory cache. Cache is cleared on every `refresh()` call
    /// (logs may change after retry).
    func loadBuildLog(for itemId: String) {
        // Check cache first
        if let cached = buildLogCache[itemId] {
            buildLogState = .loaded(cached)
            return
        }

        buildLogState = .loading
        let adapter = self.adapter

        Task {
            let result = await adapter.loadBuildLog(itemId: itemId)
            switch result {
            case .success(let log):
                self.buildLogCache[itemId] = log
                self.buildLogState = .loaded(log)
            case .failure(let error):
                self.buildLogState = .failed(error)
            }
        }
    }

    // MARK: - Mail Event Observation

    /// Subscribe to ``MailInboxStore`` for pipeline-relevant mail events.
    ///
    /// When a POLECAT_DONE, MERGE_READY, MERGED, MERGE_FAILED, or
    /// REWORK_REQUEST mail arrives, apply the stage transition immediately
    /// with animation. The 8s polling fallback catches anything missed.
    private func subscribeToMailEvents() {
        MailInboxStore.shared.$messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] messages in
                self?.processNewMailEvents(messages)
            }
            .store(in: &cancellables)
    }

    private func processNewMailEvents(_ messages: [MailMessage]) {
        // Only process new messages since last check
        guard messages.count > lastMailCount else {
            lastMailCount = messages.count
            return
        }

        let newMessages = messages.prefix(messages.count - lastMailCount)
        lastMailCount = messages.count

        guard case .loaded(let snapshot) = loadState else { return }
        var updatedQueue = snapshot.queue
        var changed = false

        for message in newMessages {
            guard let event = RefineryAdapter.parseMailEvent(message) else { continue }

            switch event {
            case .polecatDone(let beadId, _, _):
                if let index = updatedQueue.firstIndex(where: { $0.id == beadId }) {
                    if updatedQueue[index].stage != .polecatDone {
                        updatedQueue[index].stage = .polecatDone
                        changed = true
                    }
                }
                // New item may appear on next poll

            case .mergeReady(let beadId):
                if let index = updatedQueue.firstIndex(where: { $0.id == beadId }) {
                    updatedQueue[index].stage = .mergeReady
                    changed = true
                }

            case .merged(let beadId):
                if let index = updatedQueue.firstIndex(where: { $0.id == beadId }) {
                    updatedQueue[index].stage = .merged
                    changed = true
                }

            case .mergeFailed(let beadId, let error):
                if let index = updatedQueue.firstIndex(where: { $0.id == beadId }) {
                    updatedQueue[index].stage = .failed
                    changed = true
                    // Clear cached build log for this item since it may have new output
                    buildLogCache.removeValue(forKey: beadId)
                    _ = error  // Error detail available on next poll/expand
                }

            case .reworkRequest(let beadId, _):
                if let index = updatedQueue.firstIndex(where: { $0.id == beadId }) {
                    updatedQueue[index].stage = .rework
                    changed = true
                }
            }
        }

        if changed {
            // Recompute stage counts from updated queue
            let allItems = updatedQueue + snapshot.skipped
            var polecatDone = 0, mergeReady = 0, building = 0, merged = 0, failed = 0, rework = 0
            for item in allItems {
                switch item.stage {
                case .polecatDone: polecatDone += 1
                case .mergeReady: mergeReady += 1
                case .building: building += 1
                case .merged: merged += 1
                case .failed: failed += 1
                case .rework: rework += 1
                case .skipped: break
                }
            }
            let newCounts = PipelineStageCounts(
                polecatDone: polecatDone,
                mergeReady: mergeReady,
                building: building,
                merged: merged,
                failed: failed,
                rework: rework
            )
            let updatedSnapshot = RefinerySnapshot(
                health: snapshot.health,
                rigId: snapshot.rigId,
                queue: updatedQueue,
                skipped: snapshot.skipped,
                history: snapshot.history,
                stageCounts: newCounts
            )
            withAnimation(GasTownAnimation.statusChange) {
                loadState = .loaded(updatedSnapshot)
            }
        }
    }

    // MARK: - Action Result Banner

    /// Show an action result banner that auto-dismisses after 4 seconds.
    func showActionResult(_ result: RefineryActionResult) {
        withAnimation(GasTownAnimation.statusChange) {
            actionResult = result
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.actionResult == result else { return }
            withAnimation(GasTownAnimation.statusChange) {
                self.actionResult = nil
            }
        }
    }

    // MARK: - Actions

    /// Merge a single passed item.
    func mergeItem(_ id: String) {
        runAction(label: "Merge \(id)") { adapter in
            adapter.mergeItem(beadId: id)
        }
    }

    /// Merge all items with passing builds.
    func mergeAllPassed() {
        runAction(label: "Merge all passed") { adapter in
            adapter.mergeAllPassed()
        }
    }

    /// Retry a failed build.
    func retryItem(_ id: String, clean: Bool = false) {
        runAction(label: "Retry \(id)") { adapter in
            adapter.retryItem(beadId: id, clean: clean)
        }
    }

    /// Skip a failed item, unblocking the queue.
    func skipItem(_ id: String) {
        runAction(label: "Skip \(id)") { adapter in
            adapter.skipItem(beadId: id)
        }
    }

    /// Force-merge despite failing build.
    func forceMergeItem(_ id: String) {
        runAction(label: "Force merge \(id)") { adapter in
            adapter.forceMergeItem(beadId: id)
        }
    }

    /// Run an adapter action asynchronously and show the result banner.
    private func runAction(
        label: String,
        work: @escaping (RefineryAdapter) async -> Result<String, RefineryAdapterError>
    ) {
        let adapter = self.adapter

        Task {
            let result = await work(adapter)
            switch result {
            case .success(let message):
                self.showActionResult(.success(message))
                // Refresh to pick up the new state
                self.refresh(silent: true)
            case .failure(let error):
                let message: String
                switch error {
                case .cliFailure(_, _, let stderr):
                    message = "\(label) failed: \(String(stderr.prefix(120)))"
                default:
                    message = "\(label) failed"
                }
                self.showActionResult(.failure(message))
            }
        }
    }

    // MARK: - Keyboard Navigation

    /// Move selection to the next queue item.
    func selectNextItem() {
        guard case .loaded(let snapshot) = loadState else { return }
        let items = snapshot.queue
        guard !items.isEmpty else { return }

        if let currentId = selectedItemId,
           let currentIndex = items.firstIndex(where: { $0.id == currentId }),
           currentIndex + 1 < items.count {
            selectedItemId = items[currentIndex + 1].id
        } else {
            selectedItemId = items.first?.id
        }
    }

    /// Move selection to the previous queue item.
    func selectPreviousItem() {
        guard case .loaded(let snapshot) = loadState else { return }
        let items = snapshot.queue
        guard !items.isEmpty else { return }

        if let currentId = selectedItemId,
           let currentIndex = items.firstIndex(where: { $0.id == currentId }),
           currentIndex > 0 {
            selectedItemId = items[currentIndex - 1].id
        } else {
            selectedItemId = items.last?.id
        }
    }

    /// Toggle expand/collapse on the current selection.
    func toggleSelectedItem() {
        if selectedItemId != nil {
            // Already selected = expanded, collapse it
            collapseItem()
        }
    }

    /// Handle keyboard shortcut for the selected item.
    func handleKeyAction(_ key: Character) {
        guard let itemId = selectedItemId,
              case .loaded(let snapshot) = loadState,
              let item = snapshot.queue.first(where: { $0.id == itemId }) else { return }

        switch key {
        case "m", "M":
            if item.stage == .mergeReady {
                mergeItem(itemId)
            }
        case "r", "R":
            if item.stage == .failed {
                retryItem(itemId)
            }
        case "s", "S":
            if item.stage == .failed || item.stage == .rework {
                skipItem(itemId)
            }
        default:
            break
        }
    }
}

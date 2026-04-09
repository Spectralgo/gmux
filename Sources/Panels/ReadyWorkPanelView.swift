import SwiftUI

extension Notification.Name {
    static let openBeadInspector = Notification.Name("com.cmux.openBeadInspector")
}

/// SwiftUI view that renders a ReadyWorkPanel's content —
/// a list of dependency-cleared beads ready for work.
struct ReadyWorkPanelView: View {
    @ObservedObject var panel: ReadyWorkPanel
    let isFocused: Bool
    let isVisibleInUI: Bool
    let portalPriority: Int
    let onRequestPanelFocus: () -> Void

    @State private var focusFlashOpacity: Double = 0.0
    @State private var focusFlashAnimationGeneration: Int = 0
    @State private var showingSlingSheet: Bool = false
    @State private var slingRigInput: String = ""
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            switch panel.loadState {
            case .idle:
                idleView
            case .loading:
                loadingView
            case .loaded(let summaries):
                if summaries.isEmpty {
                    emptyView
                } else {
                    listView(summaries)
                }
            case .failed(let error):
                errorView(error)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundColor)
        .overlay {
            RoundedRectangle(cornerRadius: FocusFlashPattern.ringCornerRadius)
                .stroke(cmuxAccentColor().opacity(focusFlashOpacity), lineWidth: 3)
                .shadow(color: cmuxAccentColor().opacity(focusFlashOpacity * 0.35), radius: 10)
                .padding(FocusFlashPattern.ringInset)
                .allowsHitTesting(false)
        }
        .overlay {
            if isVisibleInUI {
                ReadyWorkPointerObserver(onPointerDown: onRequestPanelFocus)
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
                panel.refresh()
            default:
                break
            }
        }
        .sheet(isPresented: $showingSlingSheet) {
            slingSheet
        }
    }

    private var slingSheet: some View {
        VStack(spacing: 16) {
            Text(String(localized: "readyWork.sling.title", defaultValue: "Sling to Rig"))
                .font(.headline)

            if let beadId = panel.selectedBeadId {
                Text(beadId)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)

                TextField(
                    String(localized: "readyWork.sling.rigPlaceholder", defaultValue: "Rig name (e.g. spectralChat)"),
                    text: $slingRigInput
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)

                HStack(spacing: 12) {
                    Button(String(localized: "readyWork.sling.cancel", defaultValue: "Cancel")) {
                        showingSlingSheet = false
                        slingRigInput = ""
                    }
                    .keyboardShortcut(.cancelAction)

                    Button(String(localized: "readyWork.sling.send", defaultValue: "Sling")) {
                        let rig = slingRigInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !rig.isEmpty else { return }
                        panel.slingBead(beadId, toRig: rig)
                        showingSlingSheet = false
                        slingRigInput = ""
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(slingRigInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 320)
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(String(
                localized: "readyWork.idle.title",
                defaultValue: "Ready Work"
            ))
            .font(.headline)
            .foregroundColor(.primary)
            Text(String(
                localized: "readyWork.idle.message",
                defaultValue: "Press Refresh to load beads that are ready to work."
            ))
            .font(.caption)
            .foregroundColor(.secondary)
            refreshButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(String(
                localized: "readyWork.loading",
                defaultValue: "Loading ready work\u{2026}"
            ))
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundColor(.green)
            Text(String(
                localized: "readyWork.empty.title",
                defaultValue: "All Clear"
            ))
            .font(.headline)
            .foregroundColor(.primary)
            Text(String(
                localized: "readyWork.empty.message",
                defaultValue: "No beads are ready to work right now."
            ))
            .font(.caption)
            .foregroundColor(.secondary)
            refreshButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error

    private func errorView(_ error: BeadsAdapterError) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text(String(
                localized: "readyWork.error.title",
                defaultValue: "Beads Unavailable"
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

    // MARK: - List

    private func listView(_ summaries: [BeadSummary]) -> some View {
        VStack(spacing: 0) {
            headerBar(count: summaries.count)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(summaries) { bead in
                        beadRow(bead)
                        if bead.id == panel.selectedBeadId {
                            detailSection
                        }
                        Divider().padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    private func headerBar(count: Int) -> some View {
        HStack {
            Image(systemName: "tray.full")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
            Text(String(
                localized: "readyWork.header",
                defaultValue: "Ready Work"
            ))
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.primary)
            Text("(\(count))")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            refreshButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func beadRow(_ bead: BeadSummary) -> some View {
        let isSelected = panel.selectedBeadId == bead.id
        return Button(action: {
            if isSelected {
                panel.clearSelection()
            } else {
                panel.loadDetail(for: bead.id)
            }
        }) {
            HStack(spacing: 10) {
                priorityIndicator(bead.priority)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(bead.id)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                        typeBadge(bead.issueType)
                    }
                    Text(bead.title)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let assignee = bead.assignee, !assignee.isEmpty {
                        Text(assignee)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if bead.dependencyCount > 0 || bead.dependentCount > 0 {
                    depBadge(deps: bead.dependencyCount, dependents: bead.dependentCount)
                }
                Image(systemName: isSelected ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? selectedRowBackground : Color.clear)
    }

    private var detailSection: some View {
        Group {
            switch panel.selectedDetail {
            case .idle:
                EmptyView()
            case .loading:
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                        .padding(.vertical, 8)
                    Spacer()
                }
                .background(detailBackground)
            case .loaded(let detail):
                detailView(detail)
            case .failed(let error):
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                        .font(.system(size: 11))
                    Text(errorMessage(for: error))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(detailBackground)
            }
        }
    }

    private func detailView(_ detail: BeadDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !detail.description.isEmpty {
                Text(detail.description)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !detail.acceptanceCriteria.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(
                        localized: "readyWork.detail.acceptanceCriteria",
                        defaultValue: "Acceptance Criteria"
                    ))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    Text(detail.acceptanceCriteria.joined(separator: "\n"))
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !detail.dependencies.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(
                        localized: "readyWork.detail.dependencies",
                        defaultValue: "Dependencies"
                    ))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    ForEach(detail.dependencies, id: \.id) { dep in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(dep.status == .closed ? Color.green : Color.orange)
                                .frame(width: 6, height: 6)
                            Text(dep.id)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(dep.title)
                                .font(.system(size: 11))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            HStack(spacing: 12) {
                if let owner = detail.owner {
                    metaLabel(
                        String(localized: "readyWork.detail.owner", defaultValue: "Owner"),
                        value: owner
                    )
                }
                if let extRef = detail.externalRef {
                    metaLabel(
                        String(localized: "readyWork.detail.externalRef", defaultValue: "Ref"),
                        value: extRef
                    )
                }
                if let created = detail.createdDate {
                    metaLabel(
                        String(localized: "readyWork.detail.created", defaultValue: "Created"),
                        value: created
                    )
                }
            }

            Divider()
                .padding(.vertical, 4)

            // Action buttons
            HStack(spacing: 8) {
                Button(action: {
                    NotificationCenter.default.post(
                        name: .openBeadInspector,
                        object: nil,
                        userInfo: [
                            "beadId": detail.id,
                            "workspaceId": panel.workspaceId,
                        ]
                    )
                }) {
                    Label(
                        String(localized: "readyWork.action.openInspector", defaultValue: "Open in Inspector"),
                        systemImage: "doc.text.magnifyingglass"
                    )
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: {
                    showingSlingSheet = true
                }) {
                    Label(
                        String(localized: "readyWork.action.sling", defaultValue: "Sling to Polecat"),
                        systemImage: "paperplane"
                    )
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()
            }

            if let result = panel.actionResult {
                actionResultBanner(result)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(detailBackground)
    }

    // MARK: - Components

    private func priorityIndicator(_ priority: Int) -> some View {
        let color: Color = switch priority {
        case 1: .red
        case 2: .orange
        case 3: .yellow
        default: .gray
        }
        return Text("P\(priority)")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func typeBadge(_ type: String) -> some View {
        Text(type)
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func depBadge(deps: Int, dependents: Int) -> some View {
        HStack(spacing: 2) {
            if deps > 0 {
                HStack(spacing: 1) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8))
                    Text("\(deps)")
                        .font(.system(size: 10, design: .monospaced))
                }
                .foregroundColor(.secondary)
            }
            if dependents > 0 {
                HStack(spacing: 1) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 8))
                    Text("\(dependents)")
                        .font(.system(size: 10, design: .monospaced))
                }
                .foregroundColor(.secondary)
            }
        }
    }

    private func metaLabel(_ label: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
    }

    private var refreshButton: some View {
        Button(action: { panel.refresh() }) {
            Label(
                String(localized: "readyWork.refresh", defaultValue: "Refresh"),
                systemImage: "arrow.clockwise"
            )
            .font(.system(size: 12))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func actionResultBanner(_ result: ReadyWorkPanel.ActionResult) -> some View {
        HStack(spacing: 6) {
            switch result {
            case .success(let message):
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.green)
                    .font(.system(size: 11))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(.green)
            case .failure(let message):
                Image(systemName: "xmark.circle")
                    .foregroundColor(.red)
                    .font(.system(size: 11))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Styling

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(white: 0.12, alpha: 1.0))
            : Color(nsColor: NSColor(white: 0.98, alpha: 1.0))
    }

    private var selectedRowBackground: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(white: 0.18, alpha: 1.0))
            : Color(nsColor: NSColor(white: 0.94, alpha: 1.0))
    }

    private var detailBackground: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(white: 0.14, alpha: 1.0))
            : Color(nsColor: NSColor(white: 0.96, alpha: 1.0))
    }

    // MARK: - Error Formatting

    private func errorMessage(for error: BeadsAdapterError) -> String {
        switch error {
        case .bdCLINotFound:
            return String(
                localized: "readyWork.error.cliNotFound",
                defaultValue: "The 'bd' CLI was not found on PATH."
            )
        case .cliFailure(let cmd, let code, let stderr):
            return "\(cmd) exited \(code): \(stderr)"
        case .parseFailure(_, let detail):
            return detail
        case .routesFileUnreadable(_, let detail):
            return detail
        case .beadNotFound(let id):
            return String(
                localized: "readyWork.error.beadNotFound",
                defaultValue: "Bead '\(id)' not found."
            )
        case .commandFailed(let output):
            return output
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

private struct ReadyWorkPointerObserver: NSViewRepresentable {
    let onPointerDown: () -> Void

    func makeNSView(context: Context) -> ReadyWorkPointerObserverView {
        let view = ReadyWorkPointerObserverView()
        view.onPointerDown = onPointerDown
        return view
    }

    func updateNSView(_ nsView: ReadyWorkPointerObserverView, context: Context) {
        nsView.onPointerDown = onPointerDown
    }
}

final class ReadyWorkPointerObserverView: NSView {
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

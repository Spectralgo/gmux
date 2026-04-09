import SwiftUI

/// SwiftUI view that renders an AgentHealthPanel's content —
/// a grid of all Gas Town agents with live status indicators.
struct AgentHealthPanelView: View {
    @ObservedObject var panel: AgentHealthPanel
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
            case .loaded(let entries):
                if entries.isEmpty {
                    emptyView
                } else {
                    gridView(entries)
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
                AgentHealthPointerObserver(onPointerDown: onRequestPanelFocus)
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

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(String(
                localized: "agentHealth.idle.title",
                defaultValue: "Agent Health"
            ))
            .font(.headline)
            .foregroundColor(.primary)
            Text(String(
                localized: "agentHealth.idle.message",
                defaultValue: "Press Refresh to load agent status."
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
                localized: "agentHealth.loading",
                defaultValue: "Loading agents\u{2026}"
            ))
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(String(
                localized: "agentHealth.empty.title",
                defaultValue: "No Agents"
            ))
            .font(.headline)
            .foregroundColor(.primary)
            Text(String(
                localized: "agentHealth.empty.message",
                defaultValue: "No Gas Town agents found."
            ))
            .font(.caption)
            .foregroundColor(.secondary)
            refreshButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error

    private func errorView(_ error: AgentHealthAdapterError) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text(String(
                localized: "agentHealth.error.title",
                defaultValue: "Agent Status Unavailable"
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

    // MARK: - Grid

    private func gridView(_ entries: [AgentHealthEntry]) -> some View {
        VStack(spacing: 0) {
            headerBar(count: entries.count)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Group by rig
                    let grouped = Dictionary(grouping: entries, by: \.rig)
                    let rigOrder = orderedRigNames(from: entries)
                    ForEach(rigOrder, id: \.self) { rigName in
                        if let agents = grouped[rigName] {
                            rigSection(rigName, agents: agents)
                        }
                    }
                }
            }
        }
    }

    private func headerBar(count: Int) -> some View {
        HStack {
            Image(systemName: "person.3")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
            Text(String(
                localized: "agentHealth.header",
                defaultValue: "Agent Health"
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

    private func rigSection(_ rigName: String, agents: [AgentHealthEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(rigName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 4)
            ForEach(agents) { agent in
                agentRow(agent)
                Divider().padding(.horizontal, 16)
            }
        }
    }

    private func agentRow(_ agent: AgentHealthEntry) -> some View {
        HStack(spacing: 10) {
            // Status dot
            Circle()
                .fill(statusColor(for: agent))
                .frame(width: 8, height: 8)

            // Name
            Text(agent.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .frame(minWidth: 80, alignment: .leading)

            // Role badge
            roleBadge(agent.role)

            Spacer()

            // Work indicator
            if agent.hasWork {
                HStack(spacing: 2) {
                    Image(systemName: "hammer")
                        .font(.system(size: 10))
                    Text(String(localized: "agentHealth.working", defaultValue: "working"))
                        .font(.system(size: 10))
                }
                .foregroundColor(.blue)
            }

            // Unread mail badge
            if agent.unreadMail > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "envelope.badge")
                        .font(.system(size: 10))
                    Text("\(agent.unreadMail)")
                        .font(.system(size: 10, design: .monospaced))
                }
                .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Components

    private func roleBadge(_ role: String) -> some View {
        Text(role)
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func statusColor(for agent: AgentHealthEntry) -> Color {
        if agent.isRunning {
            return .green
        }
        return .gray
    }

    private var refreshButton: some View {
        Button(action: { panel.refresh() }) {
            Label(
                String(localized: "agentHealth.refresh", defaultValue: "Refresh"),
                systemImage: "arrow.clockwise"
            )
            .font(.system(size: 12))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    /// Preserve rig display order: "town" first, then alphabetical.
    private func orderedRigNames(from entries: [AgentHealthEntry]) -> [String] {
        var seen = Set<String>()
        var order: [String] = []
        for entry in entries {
            if seen.insert(entry.rig).inserted {
                order.append(entry.rig)
            }
        }
        // Move "town" to front if present
        if let townIndex = order.firstIndex(of: "town"), townIndex != 0 {
            order.remove(at: townIndex)
            order.insert("town", at: 0)
        }
        return order
    }

    // MARK: - Styling

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(white: 0.12, alpha: 1.0))
            : Color(nsColor: NSColor(white: 0.98, alpha: 1.0))
    }

    // MARK: - Error Formatting

    private func errorMessage(for error: AgentHealthAdapterError) -> String {
        switch error {
        case .gtCLINotFound:
            return String(
                localized: "agentHealth.error.cliNotFound",
                defaultValue: "The 'gt' CLI was not found on PATH."
            )
        case .cliFailure(let cmd, let code, let stderr):
            return "\(cmd) exited \(code): \(stderr)"
        case .parseFailure(let detail):
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

private struct AgentHealthPointerObserver: NSViewRepresentable {
    let onPointerDown: () -> Void

    func makeNSView(context: Context) -> AgentHealthPointerObserverView {
        let view = AgentHealthPointerObserverView()
        view.onPointerDown = onPointerDown
        return view
    }

    func updateNSView(_ nsView: AgentHealthPointerObserverView, context: Context) {
        nsView.onPointerDown = onPointerDown
    }
}

final class AgentHealthPointerObserverView: NSView {
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

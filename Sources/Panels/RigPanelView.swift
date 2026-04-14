import SwiftUI

/// Top-level SwiftUI view for the Rig Panel.
///
/// Matches the ``TownDashboardPanelView`` pattern: loads on appear,
/// auto-refreshes via `GasTownService.shared.$refreshTick`, and renders
/// a focus flash ring overlay.
struct RigPanelView: View {
    @ObservedObject var panel: RigPanel
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
                rigContent(snapshot)
            case .failed(let error):
                errorView(error)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GasTownColors.panelBackground(for: colorScheme))
        .overlay(alignment: .top) {
            if let result = panel.actionResult {
                GasTownActionToast(result: result)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: FocusFlashPattern.ringCornerRadius)
                .stroke(cmuxAccentColor().opacity(focusFlashOpacity), lineWidth: 3)
                .shadow(color: cmuxAccentColor().opacity(focusFlashOpacity * 0.35), radius: 10)
                .padding(FocusFlashPattern.ringInset)
                .allowsHitTesting(false)
        }
        .overlay {
            if isVisibleInUI {
                RigPanelPointerObserver(onPointerDown: onRequestPanelFocus)
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
            Text(String(localized: "rigPanel.loading", defaultValue: "Loading rig data..."))
                .font(GasTownTypography.caption)
                .foregroundColor(.secondary)
        }
    }

    private func errorView(_ error: RigPanelAdapterError) -> some View {
        VStack(spacing: GasTownSpacing.gridGap) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(GasTownColors.error)
            Text(errorMessage(for: error))
                .font(GasTownTypography.label)
                .foregroundColor(.secondary)
            Button(String(localized: "rigPanel.retry", defaultValue: "Retry")) {
                panel.refresh()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func errorMessage(for error: RigPanelAdapterError) -> String {
        switch error {
        case .rigNotFound(let rigId):
            return String(localized: "rigPanel.error.rigNotFound", defaultValue: "Rig '\(rigId)' not found")
        case .townRootNotAvailable:
            return String(localized: "rigPanel.error.noTownRoot", defaultValue: "Gas Town root not available")
        case .cliNotFound(let tool):
            return String(localized: "rigPanel.error.cliNotFound", defaultValue: "\(tool) CLI not found")
        }
    }

    // MARK: - Content

    private func rigContent(_ snapshot: RigPanelSnapshot) -> some View {
        VStack(spacing: 0) {
            RigPanelHeaderView(snapshot: snapshot, panel: panel)

            Divider()

            ScrollView {
                VStack(spacing: GasTownSpacing.sectionGap) {
                    RigTeamSection(
                        agents: snapshot.agents,
                        panel: panel
                    )
                    RigWorkSection(
                        beadCounts: snapshot.beadCounts,
                        convoys: snapshot.convoys,
                        workspaceId: panel.workspaceId
                    )
                    RigHealthSection(
                        health: snapshot.healthIndicators,
                        panel: panel
                    )
                    RigConfigSection(
                        rig: snapshot.rig,
                        workspaceId: panel.workspaceId
                    )
                }
                .padding(.vertical, GasTownSpacing.sectionGap)
                .padding(.horizontal, GasTownSpacing.rowPaddingH)
            }
        }
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

// MARK: - Pointer Observer

private struct RigPanelPointerObserver: NSViewRepresentable {
    let onPointerDown: () -> Void

    func makeNSView(context: Context) -> RigPanelPointerObserverView {
        let view = RigPanelPointerObserverView()
        view.onPointerDown = onPointerDown
        return view
    }

    func updateNSView(_ nsView: RigPanelPointerObserverView, context: Context) {
        nsView.onPointerDown = onPointerDown
    }
}

final class RigPanelPointerObserverView: NSView {
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

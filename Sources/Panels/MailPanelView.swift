import SwiftUI

/// Top-level SwiftUI view for the Mail Panel.
///
/// Master-detail layout with inbox list (left) and message detail (right).
/// Loads on appear, auto-refreshes via `GasTownService.shared.$refreshTick`.
struct MailPanelView: View {
    @ObservedObject var panel: MailPanel
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
                Color.clear
            case .loading:
                loadingView
            case .loaded:
                mailContent
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
                MailPanelPointerObserver(onPointerDown: onRequestPanelFocus)
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
        .sheet(isPresented: $panel.isComposePresented) {
            ComposeSheetView(panel: panel)
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: GasTownSpacing.gridGap) {
            ProgressView()
            Text(String(localized: "mailPanel.loading", defaultValue: "Loading mail..."))
                .font(GasTownTypography.caption)
                .foregroundColor(.secondary)
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: GasTownSpacing.gridGap) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(GasTownColors.error)
            Text(error)
                .font(GasTownTypography.label)
                .foregroundColor(.secondary)
            Button(String(localized: "mailPanel.retry", defaultValue: "Retry")) {
                panel.refresh()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Content

    private var mailContent: some View {
        VStack(spacing: 0) {
            // Toolbar: search + filter + compose
            MailToolbarView(panel: panel)

            Divider()

            // Master-detail split
            HSplitView {
                InboxListView(panel: panel)
                    .frame(minWidth: 240, idealWidth: 280)

                if let message = panel.selectedMessage {
                    if panel.isThreadView, let thread = panel.selectedThread {
                        ThreadView(
                            messages: thread,
                            panel: panel
                        )
                    } else {
                        MessageDetailView(
                            message: message,
                            panel: panel
                        )
                    }
                } else {
                    emptyDetailPlaceholder
                }
            }
        }
    }

    private var emptyDetailPlaceholder: some View {
        VStack(spacing: GasTownSpacing.gridGap) {
            Image(systemName: "envelope.open")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            Text(String(localized: "mailPanel.selectMessage", defaultValue: "Select a message to read"))
                .font(GasTownTypography.label)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(String(localized: "mailPanel.noSelection.a11y", defaultValue: "No message selected"))
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

private struct MailPanelPointerObserver: NSViewRepresentable {
    let onPointerDown: () -> Void

    func makeNSView(context: Context) -> MailPanelPointerObserverView {
        let view = MailPanelPointerObserverView()
        view.onPointerDown = onPointerDown
        return view
    }

    func updateNSView(_ nsView: MailPanelPointerObserverView, context: Context) {
        nsView.onPointerDown = onPointerDown
    }
}

final class MailPanelPointerObserverView: NSView {
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

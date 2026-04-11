import SwiftUI

/// Top-level SwiftUI view for the Convoy Board Panel.
///
/// Master-detail layout with convoy card list (left) and convoy detail (right).
/// Loads on appear, auto-refreshes every 4th tick (~32s) via `GasTownService.shared.$refreshTick`.
struct ConvoyBoardPanelView: View {
    @ObservedObject var panel: ConvoyBoardPanel
    let isFocused: Bool
    let isVisibleInUI: Bool
    let portalPriority: Int
    let onRequestPanelFocus: () -> Void

    @State private var focusFlashOpacity: Double = 0.0
    @State private var focusFlashAnimationGeneration: Int = 0
    @State private var refreshCounter: Int = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            switch panel.loadState {
            case .idle:
                Color.clear
            case .loading:
                loadingView
            case .loaded:
                boardContent
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
                ConvoyBoardPointerObserver(onPointerDown: onRequestPanelFocus)
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
            // Refresh every 4th tick (~32s)
            refreshCounter += 1
            guard refreshCounter % 4 == 0 else { return }
            switch panel.loadState {
            case .loaded, .failed:
                panel.refresh(silent: true)
            default:
                break
            }
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: GasTownSpacing.gridGap) {
            ProgressView()
            Text(String(localized: "convoyBoard.loading", defaultValue: "Loading convoys..."))
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
                .multilineTextAlignment(.center)
            Button(String(localized: "convoyBoard.retry", defaultValue: "Retry")) {
                panel.refresh()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Content

    private var strandedConvoys: [ConvoySummary] {
        panel.convoys.filter { $0.isStranded }
    }

    private var boardContent: some View {
        VStack(spacing: 0) {
            ConvoyBoardToolbar(panel: panel)

            if !strandedConvoys.isEmpty {
                StrandedConvoyBanner(
                    count: strandedConvoys.count,
                    onSlingNow: {
                        if let first = strandedConvoys.first {
                            panel.selectConvoy(first.id)
                        }
                    }
                )
            }

            Divider()

            if panel.convoys.isEmpty {
                emptyBoardView
            } else {
                HSplitView {
                    convoyList
                        .frame(minWidth: 260, idealWidth: 300)

                    if let detail = panel.selectedDetail {
                        ConvoyDetailSection(detail: detail)
                    } else {
                        emptyDetailPlaceholder
                    }
                }
            }
        }
    }

    // MARK: - Convoy List

    private var convoyList: some View {
        ScrollView {
            LazyVStack(spacing: GasTownSpacing.gridGap) {
                // Attention convoys first
                if !panel.attentionConvoys.isEmpty {
                    sectionLabel(String(
                        localized: "convoyBoard.section.attention",
                        defaultValue: "Needs Attention"
                    ))

                    ForEach(panel.attentionConvoys) { convoy in
                        ConvoyCardView(
                            convoy: convoy,
                            isSelected: panel.selectedConvoyId == convoy.id,
                            onSelect: { panel.selectConvoy(convoy.id) }
                        )
                    }
                }

                // Normal convoys
                if !panel.normalConvoys.isEmpty {
                    if !panel.attentionConvoys.isEmpty {
                        sectionLabel(String(
                            localized: "convoyBoard.section.active",
                            defaultValue: "Active"
                        ))
                    }

                    ForEach(panel.normalConvoys) { convoy in
                        ConvoyCardView(
                            convoy: convoy,
                            isSelected: panel.selectedConvoyId == convoy.id,
                            onSelect: { panel.selectConvoy(convoy.id) }
                        )
                    }
                }
            }
            .padding(GasTownSpacing.cardPadding)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(GasTownTypography.caption)
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    // MARK: - Empty States

    private var emptyBoardView: some View {
        VStack(spacing: GasTownSpacing.gridGap) {
            Image(systemName: "shippingbox")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            Text(String(localized: "convoyBoard.empty", defaultValue: "No active convoys"))
                .font(GasTownTypography.label)
                .foregroundColor(.secondary)
            if !panel.showClosed {
                Text(String(localized: "convoyBoard.emptyHint", defaultValue: "Toggle \"Show closed\" to see completed convoys"))
                    .font(GasTownTypography.caption)
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyDetailPlaceholder: some View {
        VStack(spacing: GasTownSpacing.gridGap) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            Text(String(localized: "convoyBoard.selectConvoy", defaultValue: "Select a convoy to view details"))
                .font(GasTownTypography.label)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(String(
            localized: "convoyBoard.noSelection.a11y",
            defaultValue: "No convoy selected"
        ))
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

// MARK: - Stranded Convoy Banner

private struct StrandedConvoyBanner: View {
    let count: Int
    let onSlingNow: () -> Void

    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: GasTownSpacing.gridGap) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(GasTownColors.error)
                .opacity(isPulsing ? 0.5 : 1.0)
                .animation(
                    .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                    value: isPulsing
                )
                .onAppear { isPulsing = true }

            Text(String(
                localized: "convoyBoard.stranded.message",
                defaultValue: "\(count) stranded convoy\(count == 1 ? "" : "s") \u{2014} ready work with no polecats assigned"
            ))
            .font(GasTownTypography.label)
            .foregroundColor(GasTownColors.error)

            Spacer()

            Button(String(
                localized: "convoyBoard.stranded.slingNow",
                defaultValue: "Sling Now"
            )) {
                onSlingNow()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(GasTownColors.error)
        }
        .padding(.horizontal, GasTownSpacing.rowPaddingH)
        .padding(.vertical, GasTownSpacing.rowPaddingV)
        .background(GasTownColors.error.opacity(0.15))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(
            localized: "convoyBoard.stranded.a11y",
            defaultValue: "\(count) stranded convoys need attention"
        ))
    }
}

// MARK: - Pointer Observer

private struct ConvoyBoardPointerObserver: NSViewRepresentable {
    let onPointerDown: () -> Void

    func makeNSView(context: Context) -> ConvoyBoardPointerObserverView {
        let view = ConvoyBoardPointerObserverView()
        view.onPointerDown = onPointerDown
        return view
    }

    func updateNSView(_ nsView: ConvoyBoardPointerObserverView, context: Context) {
        nsView.onPointerDown = onPointerDown
    }
}

final class ConvoyBoardPointerObserverView: NSView {
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

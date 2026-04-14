import SwiftUI

/// Top-level SwiftUI view for the Agent Profile panel.
///
/// Renders an RPG-style character sheet: header, stats grid, skills bars,
/// memories, CV chain, and a sticky actions bar.
struct AgentProfilePanelView: View {
    @ObservedObject var panel: AgentProfilePanel
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
            case .loaded:
                profileContent
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
                AgentProfilePointerObserver(onPointerDown: onRequestPanelFocus)
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
        VStack(spacing: GasTownSpacing.sectionGap) {
            ProgressView()
                .controlSize(.small)
            Text(String(localized: "agentProfile.loading", defaultValue: "Loading profile..."))
                .font(GasTownTypography.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: AgentProfileAdapterError) -> some View {
        VStack(spacing: GasTownSpacing.sectionGap) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(GasTownColors.error)
            Text(error.errorDescription)
                .font(GasTownTypography.label)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, GasTownSpacing.rowPaddingH)
            Button {
                panel.refresh()
            } label: {
                Text(String(localized: "agentProfile.retry", defaultValue: "Retry"))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Main Content

    private var profileContent: some View {
        let roleColor: Color = {
            if let role = panel.currentHealth?.role {
                return AgentRoleGroup.from(role: role).borderColor
            }
            return .accentColor
        }()

        return VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: GasTownSpacing.sectionGap) {
                    ProfileHeaderView(
                        health: panel.currentHealth,
                        agentAddress: panel.agentAddress
                    )

                    HookBeadCardView(
                        health: panel.currentHealth,
                        beadHistory: panel.beadHistory,
                        workspaceId: panel.workspaceId
                    )

                    StatsGridView(stats: panel.stats)

                    SkillsSection(skills: panel.skills, roleColor: roleColor)

                    MemorySection(
                        memories: panel.memories,
                        onAddMemory: { text in panel.addMemory(text) }
                    )

                    CVChainSection(
                        beadHistory: panel.beadHistory,
                        workspaceId: panel.workspaceId
                    )
                }
                .padding(.vertical, GasTownSpacing.sectionGap)
                .padding(.horizontal, GasTownSpacing.rowPaddingH)
            }

            Divider()

            ActionsBarView(
                agentAddress: panel.agentAddress,
                role: panel.currentHealth?.role,
                onActionResult: { panel.showActionResult($0) }
            )
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

private struct AgentProfilePointerObserver: NSViewRepresentable {
    let onPointerDown: () -> Void

    func makeNSView(context: Context) -> AgentProfilePointerNSView {
        AgentProfilePointerNSView(onPointerDown: onPointerDown)
    }

    func updateNSView(_ nsView: AgentProfilePointerNSView, context: Context) {
        nsView.onPointerDown = onPointerDown
    }
}

private class AgentProfilePointerNSView: NSView {
    var onPointerDown: () -> Void

    init(onPointerDown: @escaping () -> Void) {
        self.onPointerDown = onPointerDown
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        onPointerDown()
        super.mouseDown(with: event)
    }
}

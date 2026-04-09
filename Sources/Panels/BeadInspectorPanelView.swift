import AppKit
import SwiftUI

/// SwiftUI view that renders a BeadInspectorPanel's bead detail.
struct BeadInspectorPanelView: View {
    @ObservedObject var panel: BeadInspectorPanel
    let isFocused: Bool
    let isVisibleInUI: Bool
    let portalPriority: Int
    let onRequestPanelFocus: () -> Void

    @State private var focusFlashOpacity: Double = 0.0
    @State private var focusFlashAnimationGeneration: Int = 0
    @State private var showingAssignSheet: Bool = false
    @State private var assigneeInput: String = ""
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if panel.isLoading && panel.beadDetail == nil {
                loadingView
            } else if let detail = panel.beadDetail {
                beadDetailView(detail)
            } else {
                errorView
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
                BeadInspectorPointerObserver(onPointerDown: onRequestPanelFocus)
            }
        }
        .onChange(of: panel.focusFlashToken) { _ in
            triggerFocusFlashAnimation()
        }
        .onReceive(GasTownService.shared.$refreshTick) { _ in
            guard panel.beadDetail != nil, !panel.isLoading else { return }
            Task {
                await panel.refresh()
            }
        }
    }

    // MARK: - Detail Content

    private func beadDetailView(_ detail: BeadDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerSection(detail)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                Divider()
                    .padding(.horizontal, 16)

                statusSection(detail)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)

                if !detail.description.isEmpty {
                    Divider()
                        .padding(.horizontal, 16)
                    descriptionSection(detail)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                }

                if !detail.acceptanceCriteria.isEmpty {
                    Divider()
                        .padding(.horizontal, 16)
                    acceptanceCriteriaSection(detail)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                }

                if !detail.dependencies.isEmpty {
                    Divider()
                        .padding(.horizontal, 16)
                    dependenciesSection(detail)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                }

                Spacer(minLength: 16)

                // Action buttons
                actionsSection
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)

                if let result = panel.actionResult {
                    actionResultBanner(result)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                }

                // Refresh button at the bottom
                refreshButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Header

    private func headerSection(_ detail: BeadDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                Text(detail.id)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
                Spacer()
                if panel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            Text(detail.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Status

    private func statusSection(_ detail: BeadDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(String(localized: "beadInspector.section.status", defaultValue: "Status"))

            HStack(spacing: 16) {
                statusBadge(detail.status)

                if let priority = detail.priority {
                    HStack(spacing: 4) {
                        Image(systemName: "flag")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("P\(priority)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                if let type = detail.type {
                    HStack(spacing: 4) {
                        Image(systemName: "tag")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(type)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let owner = detail.owner, !owner.isEmpty {
                metadataRow(
                    label: String(localized: "beadInspector.field.owner", defaultValue: "Owner"),
                    value: owner
                )
            }
            if let assignee = detail.assignee, !assignee.isEmpty {
                metadataRow(
                    label: String(localized: "beadInspector.field.assignee", defaultValue: "Assignee"),
                    value: assignee
                )
            }
            if let created = detail.createdDate {
                metadataRow(
                    label: String(localized: "beadInspector.field.created", defaultValue: "Created"),
                    value: created
                )
            }
            if let updated = detail.updatedDate {
                metadataRow(
                    label: String(localized: "beadInspector.field.updated", defaultValue: "Updated"),
                    value: updated
                )
            }
            if let extRef = detail.externalRef, !extRef.isEmpty {
                metadataRow(
                    label: String(localized: "beadInspector.field.external", defaultValue: "External"),
                    value: extRef
                )
            }
        }
    }

    private func statusBadge(_ status: BeadStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: status.iconName)
                .font(.system(size: 12))
            Text(status.displayLabel)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(statusColor(status))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(statusColor(status).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
    }

    // MARK: - Description

    private func descriptionSection(_ detail: BeadDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(String(localized: "beadInspector.section.description", defaultValue: "Description"))
            Text(detail.description)
                .font(.system(size: 13))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.85) : .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Acceptance Criteria

    private func acceptanceCriteriaSection(_ detail: BeadDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(String(localized: "beadInspector.section.acceptanceCriteria", defaultValue: "Acceptance Criteria"))
            ForEach(Array(detail.acceptanceCriteria.enumerated()), id: \.offset) { _, criterion in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "checkmark.square")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                    Text(criterion)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Dependencies

    private func dependenciesSection(_ detail: BeadDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(String(localized: "beadInspector.section.dependencies", defaultValue: "Dependencies"))
            ForEach(detail.dependencies) { dep in
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(dep.id)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(dep.title)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Shared components

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
    }

    private var actionsSection: some View {
        HStack(spacing: 8) {
            Button(action: { panel.closeBead() }) {
                Label(
                    String(localized: "beadInspector.action.close", defaultValue: "Close Bead"),
                    systemImage: "xmark.circle"
                )
                .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(panel.isLoading)

            Button(action: { showingAssignSheet = true }) {
                Label(
                    String(localized: "beadInspector.action.assign", defaultValue: "Assign"),
                    systemImage: "person.badge.plus"
                )
                .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(panel.isLoading)

            Spacer()
        }
        .sheet(isPresented: $showingAssignSheet) {
            assignSheet
        }
    }

    private var assignSheet: some View {
        VStack(spacing: 16) {
            Text(String(localized: "beadInspector.assign.title", defaultValue: "Assign Bead"))
                .font(.headline)

            Text(panel.beadId)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)

            TextField(
                String(localized: "beadInspector.assign.placeholder", defaultValue: "Assignee (e.g. gmux/polecats/fury)"),
                text: $assigneeInput
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 300)

            HStack(spacing: 12) {
                Button(String(localized: "beadInspector.assign.cancel", defaultValue: "Cancel")) {
                    showingAssignSheet = false
                    assigneeInput = ""
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "beadInspector.assign.confirm", defaultValue: "Assign")) {
                    let assignee = assigneeInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !assignee.isEmpty else { return }
                    panel.assignBead(to: assignee)
                    showingAssignSheet = false
                    assigneeInput = ""
                }
                .keyboardShortcut(.defaultAction)
                .disabled(assigneeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 360)
    }

    private func actionResultBanner(_ result: BeadInspectorPanel.ActionResult) -> some View {
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
    }

    private var refreshButton: some View {
        Button {
            Task {
                await panel.refresh()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                Text(String(localized: "beadInspector.button.refresh", defaultValue: "Refresh"))
                    .font(.system(size: 12))
            }
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .disabled(panel.isLoading)
    }

    // MARK: - Loading / Error states

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text(String(localized: "beadInspector.loading", defaultValue: "Loading bead…"))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(String(localized: "beadInspector.error.title", defaultValue: "Could not load bead"))
                .font(.headline)
                .foregroundColor(.primary)
            Text(panel.beadId)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
            if let errorMessage = panel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            refreshButton
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Colors

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(white: 0.12, alpha: 1.0))
            : Color(nsColor: NSColor(white: 0.98, alpha: 1.0))
    }

    private func statusColor(_ status: BeadStatus) -> Color {
        switch status {
        case .open: return Color(nsColor: .systemGray)
        case .inProgress: return Color(nsColor: .systemBlue)
        case .blocked: return Color(nsColor: .systemRed)
        case .deferred: return Color(nsColor: .systemOrange)
        case .closed: return Color(nsColor: .systemGreen)
        case .pinned: return Color(nsColor: .systemPurple)
        case .hooked: return Color(nsColor: .systemTeal)
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

private struct BeadInspectorPointerObserver: NSViewRepresentable {
    let onPointerDown: () -> Void

    func makeNSView(context: Context) -> BeadInspectorPointerObserverView {
        let view = BeadInspectorPointerObserverView()
        view.onPointerDown = onPointerDown
        return view
    }

    func updateNSView(_ nsView: BeadInspectorPointerObserverView, context: Context) {
        nsView.onPointerDown = onPointerDown
    }
}

final class BeadInspectorPointerObserverView: NSView {
    var onPointerDown: (() -> Void)?
    private var eventMonitor: Any?

    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installEventMonitorIfNeeded()
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
        super.mouseDown(with: event)
    }

    func shouldHandle(_ event: NSEvent) -> Bool {
        guard event.type == .leftMouseDown,
              let window,
              event.window === window,
              !isHiddenOrHasHiddenAncestor else { return false }
        if PaneFirstClickFocusSettings.isEnabled(), window.isKeyWindow != true {
            return false
        }
        let point = convert(event.locationInWindow, from: nil)
        return bounds.contains(point)
    }

    func handleEventIfNeeded(_ event: NSEvent) -> NSEvent {
        guard shouldHandle(event) else { return event }
        DispatchQueue.main.async { [weak self] in
            self?.onPointerDown?()
        }
        return event
    }

    private func installEventMonitorIfNeeded() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.handleEventIfNeeded(event) ?? event
        }
    }
}

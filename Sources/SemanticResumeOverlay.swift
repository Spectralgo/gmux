import SwiftUI

// MARK: - Semantic Resume Overlay

/// Displays checkpoint-derived recovery information after app restart or crash.
/// This overlay is advisory: it shows what a polecat was working on, but does not
/// guarantee that the session can be resumed exactly. Users can jump from here
/// into the relevant worktree or dismiss.
struct SemanticResumeOverlay: View {
    let checkpoints: [GastownCheckpointContext]
    let onOpenWorktree: (GastownCheckpointContext) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            advisoryBanner
            scrollableContent
            Divider()
            footerView
        }
        .frame(width: 480, height: min(CGFloat(200 + checkpoints.count * 120), 560))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
    }

    private var headerView: some View {
        HStack {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(String(
                localized: "semanticResume.title",
                defaultValue: "Work Context Recovery"
            ))
            .font(.headline)
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(
                localized: "semanticResume.dismiss.accessibilityLabel",
                defaultValue: "Dismiss recovery overlay"
            ))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var advisoryBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(String(
                localized: "semanticResume.advisory",
                defaultValue: "Checkpoint data is advisory. Live processes are not restored."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.06))
    }

    private var scrollableContent: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(Array(checkpoints.enumerated()), id: \.offset) { _, context in
                    CheckpointCardView(
                        context: context,
                        onOpen: { onOpenWorktree(context) }
                    )
                }
            }
            .padding(12)
        }
    }

    private var footerView: some View {
        HStack {
            Text(String(
                localized: "semanticResume.footer.hint",
                defaultValue: "Open a worktree to resume where you left off."
            ))
            .font(.caption)
            .foregroundStyle(.tertiary)
            Spacer()
            Button(String(
                localized: "semanticResume.dismissAll",
                defaultValue: "Dismiss"
            )) {
                onDismiss()
            }
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Checkpoint Card

private struct CheckpointCardView: View {
    let context: GastownCheckpointContext
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            detailGrid
            if context.isStale {
                staleWarning
            }
            actionRow
        }
        .padding(12)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var headerRow: some View {
        HStack {
            Label {
                Text("\(context.rigName)/\(context.polecatName)")
                    .font(.system(.subheadline, design: .monospaced, weight: .semibold))
            } icon: {
                Image(systemName: "terminal.fill")
                    .foregroundStyle(.blue)
            }
            Spacer()
            if let fileDate = context.checkpointFileDate {
                Text(fileDate, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var detailGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            if let bead = context.checkpoint.hookedBead {
                GridRow {
                    detailLabel(String(
                        localized: "semanticResume.card.bead",
                        defaultValue: "Bead"
                    ))
                    Text(bead)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                }
            }
            if let step = context.checkpoint.step {
                GridRow {
                    detailLabel(String(
                        localized: "semanticResume.card.step",
                        defaultValue: "Step"
                    ))
                    Text(step)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                }
            }
            if let branch = context.checkpoint.branch {
                GridRow {
                    detailLabel(String(
                        localized: "semanticResume.card.branch",
                        defaultValue: "Branch"
                    ))
                    HStack(spacing: 4) {
                        Text(branch)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                        if let shortCommit = context.shortCommit {
                            Text("(\(shortCommit))")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            if let modifiedFiles = context.checkpoint.modifiedFiles, modifiedFiles > 0 {
                GridRow {
                    detailLabel(String(
                        localized: "semanticResume.card.dirtyFiles",
                        defaultValue: "Dirty files"
                    ))
                    Text(String.localizedStringWithFormat(
                        String(
                            localized: "semanticResume.card.dirtyFilesCount",
                            defaultValue: "%lld modified"
                        ),
                        modifiedFiles
                    ))
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
        }
    }

    private func detailLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 70, alignment: .trailing)
    }

    private var staleWarning: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.yellow)
            Text(String(
                localized: "semanticResume.card.stale",
                defaultValue: "Checkpoint may be outdated"
            ))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var actionRow: some View {
        HStack {
            Spacer()
            Button {
                onOpen()
            } label: {
                Label(String(
                    localized: "semanticResume.card.openWorktree",
                    defaultValue: "Open Worktree"
                ), systemImage: "folder.badge.gearshape")
                .font(.caption)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
}

// MARK: - Hosting controller for AppKit integration

final class SemanticResumeOverlayController: NSWindowController {
    private var onDismiss: (() -> Void)?

    static func show(
        checkpoints: [GastownCheckpointContext],
        relativeTo parentWindow: NSWindow?,
        onOpenWorktree: @escaping (GastownCheckpointContext) -> Void,
        onDismiss: @escaping () -> Void
    ) -> SemanticResumeOverlayController? {
        guard !checkpoints.isEmpty else { return nil }

        let overlay = SemanticResumeOverlay(
            checkpoints: checkpoints,
            onOpenWorktree: { context in
                onOpenWorktree(context)
            },
            onDismiss: onDismiss
        )

        let hostingView = NSHostingView(rootView: overlay)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let contentSize = hostingView.fittingSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = hostingView

        if let parentWindow {
            let parentFrame = parentWindow.frame
            let x = parentFrame.midX - contentSize.width / 2
            let y = parentFrame.maxY - contentSize.height - 80
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.center()
        }

        let controller = SemanticResumeOverlayController(window: panel)
        controller.onDismiss = onDismiss
        controller.showWindow(nil)
        return controller
    }

    func dismissOverlay() {
        window?.close()
        onDismiss?()
        onDismiss = nil
    }
}

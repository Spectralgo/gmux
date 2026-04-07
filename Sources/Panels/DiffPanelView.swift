import SwiftUI
import AppKit

/// SwiftUI view that renders a DiffPanel's changed files list and diff output.
struct DiffPanelView: View {
    @ObservedObject var panel: DiffPanel
    let isFocused: Bool
    let isVisibleInUI: Bool
    let portalPriority: Int
    let onRequestPanelFocus: () -> Void

    @State private var focusFlashOpacity: Double = 0.0
    @State private var focusFlashAnimationGeneration: Int = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let errorMessage = panel.errorMessage {
                errorView(errorMessage)
            } else if panel.changedFiles.isEmpty && !panel.isLoading {
                emptyStateView
            } else {
                diffContentView
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
        .onChange(of: panel.focusFlashToken) { _ in
            triggerFocusFlashAnimation()
        }
    }

    // MARK: - Content

    private var diffContentView: some View {
        HSplitView {
            fileListView
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)

            diffDetailView
                .frame(maxWidth: .infinity)
        }
    }

    private var fileListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                Text(panel.summary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                if panel.isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                } else {
                    Button(action: { panel.refresh() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "diff.refresh", defaultValue: "Refresh"))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // File list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(panel.changedFiles) { entry in
                        fileRow(entry)
                    }
                }
            }
        }
        .background(fileListBackground)
    }

    private func fileRow(_ entry: DiffFileEntry) -> some View {
        let isSelected = panel.selectedFilePath == entry.path
        return Button(action: {
            onRequestPanelFocus()
            panel.selectedFilePath = entry.path
        }) {
            HStack(spacing: 6) {
                statusBadge(entry.status)
                Text(entry.path)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(isSelected ? selectedRowBackground : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statusBadge(_ status: String) -> some View {
        let (text, color) = statusDisplay(status)
        return Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .frame(width: 16)
    }

    private func statusDisplay(_ status: String) -> (String, Color) {
        switch status {
        case "M":
            return ("M", .orange)
        case "A":
            return ("A", .green)
        case "D":
            return ("D", .red)
        case "R":
            return ("R", .blue)
        case "??":
            return ("?", .secondary)
        default:
            return (String(status.prefix(1)), .secondary)
        }
    }

    private var diffDetailView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let selectedPath = panel.selectedFilePath {
                // File path header
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                    Text(selectedPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                // Diff content
                if panel.selectedFileDiff.isEmpty {
                    VStack {
                        Spacer()
                        Text(String(localized: "diff.noChanges", defaultValue: "No changes"))
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    diffTextView(panel.selectedFileDiff)
                }
            } else {
                VStack {
                    Spacer()
                    Text(String(localized: "diff.selectFile", defaultValue: "Select a file to view changes"))
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func diffTextView(_ diff: String) -> some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(diff.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                    diffLine(String(line))
                }
            }
            .padding(12)
        }
        .textSelection(.enabled)
    }

    private func diffLine(_ line: String) -> some View {
        let (bgColor, textColor) = diffLineColors(line)
        return Text(line)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(textColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.vertical, 0.5)
            .background(bgColor)
    }

    private func diffLineColors(_ line: String) -> (Color, Color) {
        let isDark = colorScheme == .dark
        if line.hasPrefix("+++") || line.hasPrefix("---") {
            return (Color.clear, isDark ? .white.opacity(0.6) : .secondary)
        }
        if line.hasPrefix("@@") {
            let bg = isDark
                ? Color(nsColor: NSColor(red: 0.15, green: 0.15, blue: 0.35, alpha: 1.0))
                : Color(nsColor: NSColor(red: 0.88, green: 0.88, blue: 1.0, alpha: 1.0))
            let fg = isDark ? Color(nsColor: NSColor(red: 0.6, green: 0.6, blue: 1.0, alpha: 1.0)) : .blue
            return (bg, fg)
        }
        if line.hasPrefix("+") {
            let bg = isDark
                ? Color(nsColor: NSColor(red: 0.1, green: 0.22, blue: 0.1, alpha: 1.0))
                : Color(nsColor: NSColor(red: 0.9, green: 1.0, blue: 0.9, alpha: 1.0))
            let fg = isDark
                ? Color(nsColor: NSColor(red: 0.5, green: 0.9, blue: 0.5, alpha: 1.0))
                : Color(nsColor: NSColor(red: 0.1, green: 0.5, blue: 0.1, alpha: 1.0))
            return (bg, fg)
        }
        if line.hasPrefix("-") {
            let bg = isDark
                ? Color(nsColor: NSColor(red: 0.25, green: 0.1, blue: 0.1, alpha: 1.0))
                : Color(nsColor: NSColor(red: 1.0, green: 0.92, blue: 0.92, alpha: 1.0))
            let fg = isDark
                ? Color(nsColor: NSColor(red: 0.95, green: 0.5, blue: 0.5, alpha: 1.0))
                : Color(nsColor: NSColor(red: 0.6, green: 0.1, blue: 0.1, alpha: 1.0))
            return (bg, fg)
        }
        let fg = isDark ? Color.white.opacity(0.8) : Color.primary
        return (Color.clear, fg)
    }

    // MARK: - Empty/Error states

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundColor(.green)
            Text(String(localized: "diff.noChanges.title", defaultValue: "No changes"))
                .font(.headline)
                .foregroundColor(.primary)
            Text(panel.repositoryPath)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
            Text(String(localized: "diff.noChanges.message", defaultValue: "Working tree is clean."))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text(String(localized: "diff.error.title", defaultValue: "Unable to load diff"))
                .font(.headline)
                .foregroundColor(.primary)
            Text(message)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .padding(.horizontal, 24)
            Button(String(localized: "diff.error.retry", defaultValue: "Retry")) {
                panel.refresh()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Colors

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(white: 0.12, alpha: 1.0))
            : Color(nsColor: NSColor(white: 0.98, alpha: 1.0))
    }

    private var fileListBackground: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(white: 0.10, alpha: 1.0))
            : Color(nsColor: NSColor(white: 0.96, alpha: 1.0))
    }

    private var selectedRowBackground: Color {
        colorScheme == .dark
            ? Color.accentColor.opacity(0.3)
            : Color.accentColor.opacity(0.15)
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

import SwiftUI

/// Toolbar with search, filter dropdowns, thread toggle, and compose button.
struct MailToolbarView: View {
    @ObservedObject var panel: MailPanel

    var body: some View {
        HStack(spacing: GasTownSpacing.gridGap) {
            // Search field
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                TextField(
                    String(localized: "mailPanel.search.placeholder", defaultValue: "Search mail..."),
                    text: $panel.searchQuery
                )
                .textFieldStyle(.plain)
                .font(GasTownTypography.label)

                if !panel.searchQuery.isEmpty {
                    Button {
                        panel.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "mailPanel.search.clear.a11y", defaultValue: "Clear search"))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .frame(maxWidth: 220)

            // Filter bar
            FilterBarView(filter: $panel.activeFilter)

            Spacer()

            // Thread toggle
            Button {
                panel.isThreadView.toggle()
            } label: {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 13))
                    .foregroundColor(panel.isThreadView ? cmuxAccentColor() : .secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "mailPanel.threadToggle.help", defaultValue: "Toggle thread view"))
            .accessibilityLabel(String(
                localized: "mailPanel.threadToggle.a11y",
                defaultValue: panel.isThreadView ? "Disable thread view" : "Enable thread view"
            ))

            // Compose button
            Button {
                panel.isComposePresented = true
                panel.refreshRecipientDirectory()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut("n", modifiers: .command)
            .help(String(localized: "mailPanel.compose.help", defaultValue: "Compose new message"))
            .accessibilityLabel(String(localized: "mailPanel.compose.a11y", defaultValue: "Compose new message"))
        }
        .padding(.horizontal, GasTownSpacing.rowPaddingH)
        .padding(.vertical, GasTownSpacing.rowPaddingV)
    }
}

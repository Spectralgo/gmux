import SwiftUI

/// Left pane of the master-detail layout: pinned zone + message list.
struct InboxListView: View {
    @ObservedObject var panel: MailPanel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Header with counts and actions
            inboxHeader

            Divider()

            if panel.mailStore.messages.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Pinned standing orders section
                        if !panel.pinnedMessages.isEmpty {
                            pinnedSection
                        }

                        // Regular inbox messages
                        ForEach(panel.filteredMessages) { message in
                            MessageRow(
                                message: message,
                                isSelected: panel.selectedMessageID == message.id,
                                onSelect: { panel.selectMessage(message.id) }
                            )
                        }
                    }
                }
            }
        }
        .background(GasTownColors.panelBackground(for: colorScheme))
    }

    // MARK: - Header

    private var inboxHeader: some View {
        HStack {
            Text(String(localized: "mailPanel.inbox.title", defaultValue: "Inbox"))
                .font(GasTownTypography.sectionHeader)

            if panel.mailStore.hasUnread {
                Text("\(panel.mailStore.unreadCount)")
                    .font(GasTownTypography.badge)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(cmuxAccentColor()))
                    .accessibilityLabel(String(
                        localized: "mailPanel.unreadCount.a11y",
                        defaultValue: "\(panel.mailStore.unreadCount) unread messages"
                    ))
            }

            Spacer()

            if panel.mailStore.hasUnread {
                Button(String(localized: "mailPanel.markAllRead", defaultValue: "Mark All Read")) {
                    panel.mailStore.markAllRead()
                }
                .buttonStyle(.plain)
                .font(GasTownTypography.caption)
                .foregroundColor(cmuxAccentColor())
            }
        }
        .padding(.horizontal, GasTownSpacing.rowPaddingH)
        .padding(.vertical, GasTownSpacing.rowPaddingV)
    }

    // MARK: - Pinned Section

    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundColor(GasTownRoleColors.coordinator)
                Text(String(localized: "mailPanel.pinned.title", defaultValue: "Pinned"))
                    .font(GasTownTypography.badge)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, GasTownSpacing.rowPaddingH)
            .padding(.top, GasTownSpacing.rowPaddingV)
            .padding(.bottom, 4)

            ForEach(panel.pinnedMessages) { message in
                PinnedMessageRow(
                    message: message,
                    isSelected: panel.selectedMessageID == message.id,
                    onSelect: { panel.selectMessage(message.id) }
                )
            }

            Divider()
                .padding(.vertical, 4)
        }
        .background(GasTownColors.sectionBackground(for: colorScheme))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: GasTownSpacing.gridGap) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.5))
            Text(String(localized: "mailPanel.empty.title", defaultValue: "No mail yet"))
                .font(GasTownTypography.label)
                .fontWeight(.medium)
            Text(String(localized: "mailPanel.empty.description", defaultValue: "Agent mail and workflow messages will appear here."))
                .font(GasTownTypography.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(GasTownSpacing.cardPadding)
    }
}

// MARK: - Message Row

struct MessageRow: View, Equatable {
    let message: MailMessage
    let isSelected: Bool
    let onSelect: () -> Void

    static func == (lhs: MessageRow, rhs: MessageRow) -> Bool {
        lhs.message == rhs.message && lhs.isSelected == rhs.isSelected
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 8) {
                // Priority border (left edge)
                priorityBar

                // Unread dot
                Circle()
                    .fill(message.isRead ? Color.clear : cmuxAccentColor())
                    .overlay(
                        Circle()
                            .stroke(cmuxAccentColor().opacity(message.isRead ? 0.2 : 1), lineWidth: 1)
                    )
                    .frame(width: GasTownStatusDot.size, height: GasTownStatusDot.size)
                    .padding(.top, 5)

                // Role icon
                Image(systemName: GasTownRoleIcon.sfSymbol(for: senderRole))
                    .font(.system(size: 12))
                    .foregroundColor(roleColor)
                    .frame(width: 16, height: 16)
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 2) {
                    // Sender + timestamp
                    HStack {
                        Text(message.sender)
                            .font(GasTownTypography.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                            .font(GasTownTypography.caption)
                            .foregroundColor(.secondary)
                    }

                    // Subject
                    Text(message.subject.isEmpty ? message.type.displayLabel : message.subject)
                        .font(message.isRead
                            ? GasTownTypography.label
                            : .system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    // Preview text
                    if !message.body.isEmpty {
                        Text(message.body)
                            .font(GasTownTypography.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.horizontal, GasTownSpacing.rowPaddingH)
            .padding(.vertical, GasTownSpacing.rowPaddingV)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected
            ? cmuxAccentColor().opacity(0.12)
            : Color.clear)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint(String(localized: "mailPanel.messageRow.a11y.hint", defaultValue: "Double-tap to read message"))
    }

    private var priorityBar: some View {
        Rectangle()
            .fill(priorityColor)
            .frame(width: 3)
    }

    private var priorityColor: Color {
        switch message.priority {
        case 0: return GasTownColors.error
        case 1: return GasTownColors.attention
        default: return Color.clear
        }
    }

    private var senderRole: String {
        let parts = message.sender.split(separator: "/")
        if parts.count >= 2 {
            let role = String(parts[parts.count - 1])
            if role.contains("mayor") { return "mayor" }
            if role.contains("refinery") { return "refinery" }
            if role.contains("witness") { return "witness" }
            return "polecat"
        }
        if message.sender.contains("mayor") { return "mayor" }
        return "polecat"
    }

    private var roleColor: Color {
        switch senderRole {
        case "mayor": return GasTownRoleColors.coordinator
        case "refinery", "witness": return GasTownRoleColors.infrastructure
        default: return GasTownRoleColors.worker
        }
    }

    private var accessibilityDescription: String {
        let readState = message.isRead
            ? String(localized: "mailPanel.a11y.read", defaultValue: "read")
            : String(localized: "mailPanel.a11y.unread", defaultValue: "unread")
        return "\(message.sender), \(message.subject), \(readState), \(message.createdAt.formatted(date: .omitted, time: .shortened))"
    }
}

// MARK: - Pinned Message Row

struct PinnedMessageRow: View {
    let message: MailMessage
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundColor(GasTownRoleColors.coordinator)

                VStack(alignment: .leading, spacing: 2) {
                    Text(message.subject.isEmpty ? message.type.displayLabel : message.subject)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(message.sender)
                            .font(GasTownTypography.caption)
                            .foregroundColor(.secondary)
                        Text("·")
                            .font(GasTownTypography.caption)
                            .foregroundColor(.secondary)
                        Text(message.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .font(GasTownTypography.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, GasTownSpacing.rowPaddingH)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected
            ? cmuxAccentColor().opacity(0.12)
            : Color.clear)
        .accessibilityLabel(String(
            localized: "mailPanel.pinnedRow.a11y",
            defaultValue: "Pinned standing order: \(message.subject)"
        ))
        .accessibilityHint(String(localized: "mailPanel.pinnedRow.a11y.hint", defaultValue: "Double-tap to read"))
    }
}

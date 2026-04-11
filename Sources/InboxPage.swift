import SwiftUI

struct InboxPage: View {
    @EnvironmentObject var mailInboxStore: MailInboxStore
    @EnvironmentObject var tabManager: TabManager
    @Binding var selection: SidebarSelection

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if mailInboxStore.messages.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(mailInboxStore.groupedMessages, id: \.type) { group in
                            InboxGroupSection(
                                type: group.type,
                                messages: group.messages,
                                onOpen: { message in
                                    openMessage(message)
                                },
                                onClear: { message in
                                    mailInboxStore.remove(id: message.id)
                                }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text(String(localized: "inbox.title", defaultValue: "Inbox"))
                .font(.title2)
                .fontWeight(.semibold)

            if mailInboxStore.hasUnread {
                Text("\(mailInboxStore.unreadCount)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(cmuxAccentColor()))
            }

            Spacer()

            if !mailInboxStore.messages.isEmpty {
                if mailInboxStore.hasUnread {
                    Button(String(localized: "inbox.markAllRead", defaultValue: "Mark All Read")) {
                        mailInboxStore.markAllRead()
                    }
                    .buttonStyle(.bordered)
                }

                Button(String(localized: "inbox.clearAll", defaultValue: "Clear All")) {
                    mailInboxStore.clearAll()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text(String(localized: "inbox.empty.title", defaultValue: "No mail yet"))
                .font(.headline)
            Text(String(localized: "inbox.empty.description", defaultValue: "Agent mail and workflow messages will appear here."))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openMessage(_ message: MailMessage) {
        mailInboxStore.markRead(id: message.id)

        // If the message has a workspace context, jump to it
        if let workspaceId = message.provenance.workspaceId {
            DispatchQueue.main.async {
                _ = AppDelegate.shared?.openNotification(
                    tabId: workspaceId,
                    surfaceId: nil,
                    notificationId: nil
                )
                selection = .tabs
            }
        }
    }
}

private struct InboxGroupSection: View {
    let type: MailMessageType
    let messages: [MailMessage]
    let onOpen: (MailMessage) -> Void
    let onClear: (MailMessage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: type.iconName)
                    .foregroundColor(colorForType(type))
                    .font(.system(size: 14, weight: .semibold))
                Text(type.displayLabel)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Text("(\(messages.count))")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            }
            .padding(.leading, 4)

            ForEach(messages) { message in
                InboxMessageRow(
                    message: message,
                    onOpen: { onOpen(message) },
                    onClear: { onClear(message) }
                )
            }
        }
    }

    private func colorForType(_ type: MailMessageType) -> Color {
        switch type {
        case .mergeReady: return .orange
        case .polecatDone: return .green
        case .merged: return cmuxAccentColor()
        case .mergeFailed: return Color(GasTownColors.error)
        case .reworkRequest: return .purple
        case .info: return .secondary
        }
    }
}

private struct InboxMessageRow: View {
    let message: MailMessage
    let onOpen: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(message.isRead ? Color.clear : cmuxAccentColor())
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(cmuxAccentColor().opacity(message.isRead ? 0.2 : 1), lineWidth: 1)
                        )
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(message.subject.isEmpty
                                ? message.type.displayLabel
                                : message.subject)
                                .font(.headline)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Spacer()
                            Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if !message.body.isEmpty {
                            Text(message.body)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                        }

                        HStack(spacing: 8) {
                            provenancePill(label: message.sender, icon: "person")

                            if let beadId = message.provenance.beadId {
                                provenancePill(label: beadId, icon: "circlebadge")
                            }

                            if let convoyId = message.provenance.convoyId {
                                provenancePill(label: convoyId, icon: "shippingbox")
                            }

                            if let branch = message.provenance.branch {
                                provenancePill(label: branch, icon: "arrow.triangle.branch")
                            }

                            if let polecatName = message.provenance.polecatName {
                                provenancePill(label: polecatName, icon: "bolt")
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.trailing, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("InboxRow.\(message.id.uuidString)")

            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func provenancePill(label: String, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(label)
                .font(.system(size: 10))
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
        )
    }
}

import SwiftUI

/// Chronological thread display showing all messages in a conversation.
struct ThreadView: View {
    let messages: [MailMessage]
    @ObservedObject var panel: MailPanel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Thread header
            threadHeader

            Divider()

            // Thread messages
            ScrollView {
                LazyVStack(spacing: GasTownSpacing.gridGap) {
                    ForEach(messages) { message in
                        ThreadMessageBubble(message: message)
                    }
                }
                .padding(GasTownSpacing.cardPadding)
            }

            Divider()

            // Reply bar (reply to last message in thread)
            if let lastMessage = messages.last {
                QuickReplyBar(
                    message: lastMessage,
                    panel: panel
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GasTownColors.panelBackground(for: colorScheme))
    }

    private var threadHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(messages.first?.subject ?? "")
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    // Participant icons
                    let participants = uniqueParticipants
                    ForEach(participants.prefix(5), id: \.self) { sender in
                        Image(systemName: GasTownRoleIcon.sfSymbol(for: roleForSender(sender)))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Text(String(
                        localized: "mailPanel.thread.count",
                        defaultValue: "\(messages.count) messages"
                    ))
                    .font(GasTownTypography.caption)
                    .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .padding(GasTownSpacing.cardPadding)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(
            localized: "mailPanel.thread.header.a11y",
            defaultValue: "Thread: \(messages.first?.subject ?? ""), \(messages.count) messages"
        ))
    }

    private var uniqueParticipants: [String] {
        var seen = Set<String>()
        return messages.compactMap { msg in
            if seen.contains(msg.sender) { return nil }
            seen.insert(msg.sender)
            return msg.sender
        }
    }

    private func roleForSender(_ sender: String) -> String {
        if sender.contains("mayor") { return "mayor" }
        if sender.contains("refinery") { return "refinery" }
        if sender.contains("witness") { return "witness" }
        if sender.contains("crew") { return "crew" }
        return "polecat"
    }
}

// MARK: - Thread Message Bubble

struct ThreadMessageBubble: View {
    let message: MailMessage
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Sender + time
            HStack {
                Image(systemName: GasTownRoleIcon.sfSymbol(for: roleForSender))
                    .font(.system(size: 11))
                    .foregroundColor(roleColor)
                Text(message.sender)
                    .font(GasTownTypography.label)
                    .fontWeight(.medium)
                Spacer()
                Text(message.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(GasTownTypography.caption)
                    .foregroundColor(.secondary)
            }

            // Body
            Text(message.body)
                .font(GasTownTypography.label)
                .foregroundColor(.primary)
                .textSelection(.enabled)

            // Provenance pills (if any)
            if !message.provenance.isEmpty {
                HStack(spacing: 4) {
                    if let beadId = message.provenance.beadId {
                        provenancePill(label: beadId, icon: "circlebadge")
                    }
                    if let polecatName = message.provenance.polecatName {
                        provenancePill(label: polecatName, icon: "bolt")
                    }
                    if let branch = message.provenance.branch {
                        provenancePill(label: branch, icon: "arrow.triangle.branch")
                    }
                }
            }
        }
        .padding(GasTownSpacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(GasTownColors.sectionBackground(for: colorScheme))
        )
    }

    private func provenancePill(label: String, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(label)
                .font(GasTownTypography.badge)
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
        )
    }

    private var roleForSender: String {
        if message.sender.contains("mayor") { return "mayor" }
        if message.sender.contains("refinery") { return "refinery" }
        if message.sender.contains("witness") { return "witness" }
        if message.sender.contains("crew") { return "crew" }
        return "polecat"
    }

    private var roleColor: Color {
        switch roleForSender {
        case "mayor": return GasTownRoleColors.coordinator
        case "refinery", "witness": return GasTownRoleColors.infrastructure
        case "crew": return GasTownRoleColors.specialist
        default: return GasTownRoleColors.worker
        }
    }
}

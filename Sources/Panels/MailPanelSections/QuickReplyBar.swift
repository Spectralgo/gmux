import SwiftUI

/// Inline reply bar at the bottom of the message detail pane.
struct QuickReplyBar: View {
    let message: MailMessage
    @ObservedObject var panel: MailPanel
    @State private var replyText: String = ""
    @FocusState private var isReplyFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrowshape.turn.up.left")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            TextField(
                String(localized: "mailPanel.reply.placeholder", defaultValue: "Reply to \(message.sender)..."),
                text: $replyText
            )
            .textFieldStyle(.plain)
            .font(GasTownTypography.label)
            .focused($isReplyFocused)
            .onSubmit {
                sendReply()
            }
            .accessibilityLabel(String(
                localized: "mailPanel.reply.a11y",
                defaultValue: "Reply to \(message.sender)"
            ))
            .accessibilityHint(String(
                localized: "mailPanel.reply.hint.a11y",
                defaultValue: "Type reply and press Enter to send"
            ))

            Button {
                sendReply()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(replyText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, GasTownSpacing.cardPadding)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func sendReply() {
        let text = replyText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        panel.sendMail(
            to: message.sender,
            subject: "Re: \(message.subject)",
            body: text,
            replyTo: message.id
        )

        replyText = ""
        isReplyFocused = false
    }
}

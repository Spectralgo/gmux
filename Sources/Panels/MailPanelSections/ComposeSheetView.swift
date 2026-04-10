import SwiftUI

/// Modal compose sheet for new messages.
struct ComposeSheetView: View {
    @ObservedObject var panel: MailPanel
    @Environment(\.dismiss) private var dismiss

    @State private var recipient: String = ""
    @State private var subject: String = ""
    @State private var messageBody: String = ""
    @State private var priority: Int = 2
    @State private var isPinned: Bool = false
    @State private var recipientSuggestions: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text(String(localized: "mailPanel.compose.title", defaultValue: "New Message"))
                    .font(.headline)
                Spacer()
                Button(String(localized: "mailPanel.compose.cancel", defaultValue: "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding()

            Divider()

            // Form
            VStack(alignment: .leading, spacing: 12) {
                // Recipient
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "mailPanel.compose.to", defaultValue: "To"))
                        .font(GasTownTypography.caption)
                        .foregroundColor(.secondary)

                    ZStack(alignment: .topLeading) {
                        TextField(
                            String(localized: "mailPanel.compose.to.placeholder", defaultValue: "e.g. mayor/, gmux/witness"),
                            text: $recipient
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(GasTownTypography.label)
                        .onChange(of: recipient) { newValue in
                            updateSuggestions(for: newValue)
                        }

                        // Autocomplete suggestions
                        if !recipientSuggestions.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(recipientSuggestions, id: \.self) { suggestion in
                                    Button {
                                        recipient = suggestion
                                        recipientSuggestions = []
                                    } label: {
                                        Text(suggestion)
                                            .font(GasTownTypography.label)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .shadow(radius: 4)
                            )
                            .offset(y: 30)
                            .zIndex(1)
                        }
                    }
                }

                // Subject
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "mailPanel.compose.subject", defaultValue: "Subject"))
                        .font(GasTownTypography.caption)
                        .foregroundColor(.secondary)
                    TextField(
                        String(localized: "mailPanel.compose.subject.placeholder", defaultValue: "Subject"),
                        text: $subject
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(GasTownTypography.label)
                }

                // Priority + Pin toggle
                HStack(spacing: GasTownSpacing.sectionGap) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "mailPanel.compose.priority", defaultValue: "Priority"))
                            .font(GasTownTypography.caption)
                            .foregroundColor(.secondary)
                        Picker("", selection: $priority) {
                            Text(String(localized: "mailPanel.compose.priority.urgent", defaultValue: "Urgent")).tag(0)
                            Text(String(localized: "mailPanel.compose.priority.high", defaultValue: "High")).tag(1)
                            Text(String(localized: "mailPanel.compose.priority.normal", defaultValue: "Normal")).tag(2)
                            Text(String(localized: "mailPanel.compose.priority.low", defaultValue: "Low")).tag(3)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    Toggle(isOn: $isPinned) {
                        HStack(spacing: 4) {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 11))
                            Text(String(localized: "mailPanel.compose.pin", defaultValue: "Pin as standing order"))
                                .font(GasTownTypography.label)
                        }
                    }
                    .toggleStyle(.checkbox)
                }

                // Body
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "mailPanel.compose.body", defaultValue: "Message"))
                        .font(GasTownTypography.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $messageBody)
                        .font(GasTownTypography.label)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                }
            }
            .padding()

            Divider()

            // Send button
            HStack {
                Spacer()
                Button(String(localized: "mailPanel.compose.send", defaultValue: "Send")) {
                    sendMessage()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 520, height: 480)
    }

    private var isValid: Bool {
        !recipient.trimmingCharacters(in: .whitespaces).isEmpty &&
        !subject.trimmingCharacters(in: .whitespaces).isEmpty &&
        !messageBody.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func updateSuggestions(for text: String) {
        guard !text.isEmpty else {
            recipientSuggestions = []
            return
        }
        recipientSuggestions = panel.recipientDirectory
            .filter { $0.lowercased().contains(text.lowercased()) }
            .prefix(5)
            .map { $0 }
    }

    private func sendMessage() {
        guard isValid else { return }

        panel.sendMail(
            to: recipient.trimmingCharacters(in: .whitespaces),
            subject: subject.trimmingCharacters(in: .whitespaces),
            body: messageBody.trimmingCharacters(in: .whitespaces),
            pinned: isPinned
        )

        dismiss()
    }
}

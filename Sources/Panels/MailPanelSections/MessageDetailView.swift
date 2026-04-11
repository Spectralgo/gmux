import SwiftUI

/// Right pane showing the full message with provenance bar and action buttons.
struct MessageDetailView: View {
    let message: MailMessage
    @ObservedObject var panel: MailPanel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: GasTownSpacing.sectionGap) {
                    messageHeader
                    messageBody
                    if !message.provenance.isEmpty {
                        provenanceBar
                    }
                }
                .padding(GasTownSpacing.cardPadding)
            }

            Divider()

            // Action bar + quick reply
            VStack(spacing: 0) {
                actionBar
                QuickReplyBar(
                    message: message,
                    panel: panel
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GasTownColors.panelBackground(for: colorScheme))
    }

    // MARK: - Header

    private var messageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                // Sender info
                HStack(spacing: 6) {
                    Image(systemName: GasTownRoleIcon.sfSymbol(for: senderRole))
                        .font(.system(size: 16))
                        .foregroundColor(roleColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.sender)
                            .font(GasTownTypography.label)
                            .fontWeight(.medium)
                        Text(message.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(GasTownTypography.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Type badge with severity color
                HStack(spacing: 3) {
                    Image(systemName: message.type.iconName)
                        .font(.system(size: 10))
                    Text(message.type.displayLabel)
                        .font(GasTownTypography.badge)
                }
                .foregroundColor(message.type.severityColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(message.type.severityColor.opacity(0.12))
                )
            }

            // Subject
            Text(message.subject.isEmpty ? message.type.displayLabel : message.subject)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
        }
    }

    // MARK: - Parsed Body Fields

    /// Known structured field keys that appear as "Key: value" lines in message bodies.
    private static let structuredFieldKeys: Set<String> = [
        "Branch", "Polecat", "Rig", "Target", "Bead", "Convoy", "Author", "Stage",
    ]

    /// A parsed key-value field from the message body.
    private struct BodyField: Identifiable {
        let key: String
        let value: String
        var id: String { key }
    }

    /// Parse structured fields from the body and return (fields, remainingBody).
    private var parsedBody: (fields: [BodyField], remainder: String) {
        var fields: [BodyField] = []
        var remainderLines: [String] = []
        var seenKeys = Set<String>()

        for line in message.body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let colonIndex = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[trimmed.startIndex..<colonIndex])
                    .trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: colonIndex)...])
                    .trimmingCharacters(in: .whitespaces)
                if Self.structuredFieldKeys.contains(key), !value.isEmpty, !seenKeys.contains(key) {
                    seenKeys.insert(key)
                    fields.append(BodyField(key: key, value: value))
                    continue
                }
            }
            remainderLines.append(line)
        }

        let remainder = remainderLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (fields, remainder)
    }

    // MARK: - Body

    private var messageBody: some View {
        let parsed = parsedBody
        return VStack(alignment: .leading, spacing: GasTownSpacing.sectionGap) {
            if !parsed.fields.isEmpty {
                structuredFieldsSection(parsed.fields)
            }
            if !parsed.remainder.isEmpty {
                Text(parsed.remainder)
                    .font(GasTownTypography.label)
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Structured Fields Section

    private func structuredFieldsSection(_ fields: [BodyField]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(fields) { field in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(field.key)
                        .font(GasTownTypography.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 56, alignment: .trailing)

                    fieldValue(for: field)
                }
            }
        }
        .padding(GasTownSpacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(GasTownColors.sectionBackground(for: colorScheme))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "mailPanel.structuredFields.a11y",
                                   defaultValue: "Message details"))
    }

    /// Render a field value — clickable pill for Bead, Convoy, Polecat/Author; plain text otherwise.
    @ViewBuilder
    private func fieldValue(for field: BodyField) -> some View {
        switch field.key {
        case "Bead":
            fieldPill(label: field.value, icon: "circlebadge") {
                navigateToBead(field.value)
            }
            .accessibilityHint(String(localized: "mailPanel.field.bead.hint.a11y",
                                      defaultValue: "Opens bead inspector"))
        case "Convoy":
            fieldPill(label: field.value, icon: "shippingbox") {
                navigateToConvoy(field.value)
            }
            .accessibilityHint(String(localized: "mailPanel.field.convoy.hint.a11y",
                                      defaultValue: "Opens convoy board"))
        case "Polecat", "Author":
            fieldPill(label: field.value, icon: "bolt") {
                navigateToAgent(field.value)
            }
            .accessibilityHint(String(localized: "mailPanel.field.agent.hint.a11y",
                                      defaultValue: "Opens agent profile"))
        default:
            Text(field.value)
                .font(GasTownTypography.data)
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
    }

    /// Clickable capsule pill for navigable field values.
    private func fieldPill(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(label)
                    .font(GasTownTypography.badge)
            }
            .foregroundColor(cmuxAccentColor())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(GasTownColors.sectionBackground(for: colorScheme))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    // MARK: - Provenance Bar

    private var provenanceBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "mailPanel.provenance.title", defaultValue: "Related"))
                .font(GasTownTypography.badge)
                .foregroundColor(.secondary)

            HStack(spacing: GasTownSpacing.gridGap) {
                if let beadId = message.provenance.beadId {
                    provenancePill(
                        label: beadId,
                        icon: "circlebadge",
                        action: { navigateToBead(beadId) }
                    )
                }
                if let convoyId = message.provenance.convoyId {
                    provenancePill(label: convoyId, icon: "shippingbox", action: nil)
                }
                if let branch = message.provenance.branch {
                    provenancePill(label: branch, icon: "arrow.triangle.branch", action: nil)
                }
                if let polecatName = message.provenance.polecatName {
                    provenancePill(
                        label: polecatName,
                        icon: "bolt",
                        action: { navigateToAgent(polecatName) }
                    )
                }
            }
        }
        .padding(GasTownSpacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(GasTownColors.sectionBackground(for: colorScheme))
        )
    }

    private func provenancePill(label: String, icon: String, action: (() -> Void)?) -> some View {
        Group {
            if let action {
                Button(action: action) {
                    pillContent(label: label, icon: icon, isLink: true)
                }
                .buttonStyle(.plain)
            } else {
                pillContent(label: label, icon: icon, isLink: false)
            }
        }
    }

    private func pillContent(label: String, icon: String, isLink: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(label)
                .font(GasTownTypography.badge)
        }
        .foregroundColor(isLink ? cmuxAccentColor() : .secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
        )
        .accessibilityLabel(isLink
            ? String(localized: "mailPanel.provenance.link.a11y", defaultValue: "Related \(icon == "circlebadge" ? "bead" : "agent") \(label)")
            : label)
        .accessibilityHint(isLink
            ? String(localized: "mailPanel.provenance.link.hint.a11y", defaultValue: "Double-tap to open")
            : "")
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: GasTownSpacing.gridGap) {
            Button {
                panel.archiveMessage(message.id)
            } label: {
                Label(
                    String(localized: "mailPanel.action.archive", defaultValue: "Archive"),
                    systemImage: "archivebox"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel(String(localized: "mailPanel.action.archive.a11y", defaultValue: "Archive message"))
            .accessibilityHint(String(localized: "mailPanel.action.archive.hint.a11y", defaultValue: "Moves message to archive"))

            Button {
                panel.togglePin(message.id)
            } label: {
                Label(
                    message.isPinned
                        ? String(localized: "mailPanel.action.unpin", defaultValue: "Unpin")
                        : String(localized: "mailPanel.action.pin", defaultValue: "Pin"),
                    systemImage: message.isPinned ? "pin.slash" : "pin"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel(message.isPinned
                ? String(localized: "mailPanel.action.unpin.a11y", defaultValue: "Unpin")
                : String(localized: "mailPanel.action.pin.a11y", defaultValue: "Pin as standing order"))
            .accessibilityHint(String(localized: "mailPanel.action.pin.hint.a11y", defaultValue: "Keeps message at top of inbox"))

            Spacer()

            Button {
                panel.deleteMessage(message.id)
            } label: {
                Label(
                    String(localized: "mailPanel.action.delete", defaultValue: "Delete"),
                    systemImage: "trash"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .foregroundColor(GasTownColors.error)
        }
        .padding(.horizontal, GasTownSpacing.cardPadding)
        .padding(.vertical, 6)
    }

    // MARK: - Navigation

    private func navigateToBead(_ beadId: String) {
        NotificationCenter.default.post(
            name: .openBeadInspector,
            object: nil,
            userInfo: ["beadId": beadId]
        )
    }

    private func navigateToAgent(_ agentName: String) {
        NotificationCenter.default.post(
            name: .openAgentProfile,
            object: nil,
            userInfo: ["agentAddress": agentName]
        )
    }

    private func navigateToConvoy(_ convoyId: String) {
        NotificationCenter.default.post(
            name: .openConvoyBoard,
            object: nil,
            userInfo: ["convoyId": convoyId]
        )
    }

    // MARK: - Helpers

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
}

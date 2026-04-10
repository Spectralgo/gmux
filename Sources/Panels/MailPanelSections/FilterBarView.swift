import SwiftUI

/// Filter dropdowns for sender, priority, type, and read status.
struct FilterBarView: View {
    @Binding var filter: MailFilter

    var body: some View {
        HStack(spacing: 4) {
            // Type filter
            Menu {
                Button(String(localized: "mailPanel.filter.allTypes", defaultValue: "All Types")) {
                    filter.type = nil
                }
                Divider()
                ForEach(MailMessageType.allCases, id: \.self) { type in
                    Button {
                        filter.type = type
                    } label: {
                        Label(type.displayLabel, systemImage: type.iconName)
                    }
                }
            } label: {
                filterLabel(
                    text: filter.type?.displayLabel
                        ?? String(localized: "mailPanel.filter.type", defaultValue: "Type"),
                    isActive: filter.type != nil
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Priority filter
            Menu {
                Button(String(localized: "mailPanel.filter.allPriorities", defaultValue: "All Priorities")) {
                    filter.priority = nil
                }
                Divider()
                ForEach(0..<5) { level in
                    Button {
                        filter.priority = level
                    } label: {
                        Text(priorityLabel(level))
                    }
                }
            } label: {
                filterLabel(
                    text: filter.priority.map { priorityLabel($0) }
                        ?? String(localized: "mailPanel.filter.priority", defaultValue: "Priority"),
                    isActive: filter.priority != nil
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Read status filter
            Menu {
                ForEach(MailReadStatus.allCases, id: \.self) { status in
                    Button {
                        filter.readStatus = status == .all ? nil : status
                    } label: {
                        Text(readStatusLabel(status))
                    }
                }
            } label: {
                filterLabel(
                    text: filter.readStatus.map { readStatusLabel($0) }
                        ?? String(localized: "mailPanel.filter.status", defaultValue: "Status"),
                    isActive: filter.readStatus != nil
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Clear all filters
            if filter.isActive {
                Button {
                    filter = .empty
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "mailPanel.filter.clearAll.a11y", defaultValue: "Clear all filters"))
            }
        }
    }

    private func filterLabel(text: String, isActive: Bool) -> some View {
        Text(text)
            .font(GasTownTypography.badge)
            .foregroundColor(isActive ? cmuxAccentColor() : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive
                        ? cmuxAccentColor().opacity(0.12)
                        : Color(nsColor: .quaternaryLabelColor).opacity(0.3))
            )
    }

    private func priorityLabel(_ level: Int) -> String {
        switch level {
        case 0: return String(localized: "mailPanel.priority.urgent", defaultValue: "Urgent")
        case 1: return String(localized: "mailPanel.priority.high", defaultValue: "High")
        case 2: return String(localized: "mailPanel.priority.normal", defaultValue: "Normal")
        case 3: return String(localized: "mailPanel.priority.low", defaultValue: "Low")
        case 4: return String(localized: "mailPanel.priority.backlog", defaultValue: "Backlog")
        default: return String(localized: "mailPanel.priority.unknown", defaultValue: "Unknown")
        }
    }

    private func readStatusLabel(_ status: MailReadStatus) -> String {
        switch status {
        case .unread: return String(localized: "mailPanel.readStatus.unread", defaultValue: "Unread")
        case .read: return String(localized: "mailPanel.readStatus.read", defaultValue: "Read")
        case .all: return String(localized: "mailPanel.readStatus.all", defaultValue: "All")
        }
    }
}

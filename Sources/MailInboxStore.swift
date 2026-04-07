import Foundation

/// Message types from the Gas Town mail protocol.
enum MailMessageType: String, Codable, CaseIterable {
    case polecatDone = "POLECAT_DONE"
    case mergeReady = "MERGE_READY"
    case merged = "MERGED"
    case info = "INFO"

    var displayLabel: String {
        switch self {
        case .polecatDone: return String(localized: "inbox.messageType.polecatDone", defaultValue: "Polecat Done")
        case .mergeReady: return String(localized: "inbox.messageType.mergeReady", defaultValue: "Merge Ready")
        case .merged: return String(localized: "inbox.messageType.merged", defaultValue: "Merged")
        case .info: return String(localized: "inbox.messageType.info", defaultValue: "Info")
        }
    }

    var iconName: String {
        switch self {
        case .polecatDone: return "checkmark.circle.fill"
        case .mergeReady: return "arrow.triangle.merge"
        case .merged: return "arrow.triangle.pull"
        case .info: return "info.circle"
        }
    }

    var groupOrder: Int {
        switch self {
        case .mergeReady: return 0
        case .polecatDone: return 1
        case .merged: return 2
        case .info: return 3
        }
    }
}

/// Provenance context for a mail message, linking back to the originating work.
struct MailProvenance: Codable, Hashable {
    let beadId: String?
    let convoyId: String?
    let polecatName: String?
    let branch: String?
    let workspaceId: UUID?

    var isEmpty: Bool {
        beadId == nil && convoyId == nil && polecatName == nil && branch == nil && workspaceId == nil
    }
}

/// A single mail message in the inbox.
struct MailMessage: Identifiable, Hashable {
    let id: UUID
    let type: MailMessageType
    let subject: String
    let body: String
    let sender: String
    let provenance: MailProvenance
    let createdAt: Date
    var isRead: Bool
}

/// Observable store managing the mail inbox. Singleton pattern matching TerminalNotificationStore.
@MainActor
final class MailInboxStore: ObservableObject {
    static let shared = MailInboxStore()

    @Published private(set) var messages: [MailMessage] = []

    var unreadCount: Int {
        messages.count(where: { !$0.isRead })
    }

    var hasUnread: Bool {
        messages.contains(where: { !$0.isRead })
    }

    /// Messages grouped by type, sorted by type priority then recency.
    var groupedMessages: [(type: MailMessageType, messages: [MailMessage])] {
        let grouped = Dictionary(grouping: messages, by: { $0.type })
        return grouped
            .sorted { $0.key.groupOrder < $1.key.groupOrder }
            .map { (type: $0.key, messages: $0.value) }
    }

    func add(_ message: MailMessage) {
        messages.insert(message, at: 0)
    }

    func markRead(id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].isRead = true
    }

    func markAllRead() {
        for index in messages.indices {
            messages[index].isRead = true
        }
    }

    func remove(id: UUID) {
        messages.removeAll(where: { $0.id == id })
    }

    func clearAll() {
        messages.removeAll()
    }

    func clearByType(_ type: MailMessageType) {
        messages.removeAll(where: { $0.type == type })
    }

    /// Create a mail message from parsed socket command options.
    static func createFromOptions(
        type typeRaw: String?,
        subject: String?,
        body: String?,
        sender: String?,
        beadId: String?,
        convoyId: String?,
        polecatName: String?,
        branch: String?,
        workspaceId: UUID?
    ) -> MailMessage? {
        guard let typeRaw, let type = MailMessageType(rawValue: typeRaw.uppercased()) else {
            return nil
        }

        let provenance = MailProvenance(
            beadId: beadId,
            convoyId: convoyId,
            polecatName: polecatName,
            branch: branch,
            workspaceId: workspaceId
        )

        return MailMessage(
            id: UUID(),
            type: type,
            subject: subject ?? "",
            body: body ?? "",
            sender: sender ?? "unknown",
            provenance: provenance,
            createdAt: Date(),
            isRead: false
        )
    }

    /// Serialize messages to JSON-compatible dictionaries for list command output.
    func serializeMessages() -> [[String: Any]] {
        messages.map { msg in
            var dict: [String: Any] = [
                "id": msg.id.uuidString,
                "type": msg.type.rawValue,
                "subject": msg.subject,
                "body": msg.body,
                "sender": msg.sender,
                "is_read": msg.isRead,
                "created_at": ISO8601DateFormatter().string(from: msg.createdAt),
            ]
            if let beadId = msg.provenance.beadId { dict["bead_id"] = beadId }
            if let convoyId = msg.provenance.convoyId { dict["convoy_id"] = convoyId }
            if let polecatName = msg.provenance.polecatName { dict["polecat"] = polecatName }
            if let branch = msg.provenance.branch { dict["branch"] = branch }
            if let workspaceId = msg.provenance.workspaceId { dict["workspace_id"] = workspaceId.uuidString }
            return dict
        }
    }
}

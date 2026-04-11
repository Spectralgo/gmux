import Foundation
import SwiftUI

/// Message types from the Gas Town mail protocol.
enum MailMessageType: String, Codable, CaseIterable {
    case polecatDone = "POLECAT_DONE"
    case mergeReady = "MERGE_READY"
    case merged = "MERGED"
    case mergeFailed = "MERGE_FAILED"
    case reworkRequest = "REWORK_REQUEST"
    case help = "HELP"
    case handoff = "HANDOFF"
    case witnessPing = "WITNESS_PING"
    case info = "INFO"

    var displayLabel: String {
        switch self {
        case .polecatDone: return String(localized: "inbox.messageType.polecatDone", defaultValue: "Polecat Done")
        case .mergeReady: return String(localized: "inbox.messageType.mergeReady", defaultValue: "Merge Ready")
        case .merged: return String(localized: "inbox.messageType.merged", defaultValue: "Merged")
        case .mergeFailed: return String(localized: "inbox.messageType.mergeFailed", defaultValue: "Merge Failed")
        case .reworkRequest: return String(localized: "inbox.messageType.reworkRequest", defaultValue: "Rework Request")
        case .help: return String(localized: "inbox.messageType.help", defaultValue: "Help")
        case .handoff: return String(localized: "inbox.messageType.handoff", defaultValue: "Handoff")
        case .witnessPing: return String(localized: "inbox.messageType.witnessPing", defaultValue: "Witness Ping")
        case .info: return String(localized: "inbox.messageType.info", defaultValue: "Info")
        }
    }

    var iconName: String {
        switch self {
        case .polecatDone: return "checkmark.circle.fill"
        case .mergeReady: return "arrow.triangle.merge"
        case .merged: return "arrow.triangle.pull"
        case .mergeFailed: return "xmark.circle.fill"
        case .reworkRequest: return "arrow.triangle.2.circlepath"
        case .help: return "exclamationmark.bubble.fill"
        case .handoff: return "arrow.right.arrow.left"
        case .witnessPing: return "eye.fill"
        case .info: return "info.circle"
        }
    }

    /// Severity-based color for visual hierarchy in message lists.
    var severityColor: Color {
        switch self {
        case .mergeFailed, .reworkRequest, .help:
            return GasTownColors.error
        case .polecatDone, .mergeReady, .handoff:
            return .secondary
        case .merged:
            return GasTownColors.active
        case .witnessPing:
            return GasTownColors.idle.opacity(0.5)
        case .info:
            return .secondary
        }
    }

    var groupOrder: Int {
        switch self {
        case .mergeFailed: return 0
        case .reworkRequest: return 1
        case .help: return 2
        case .mergeReady: return 3
        case .polecatDone: return 4
        case .handoff: return 5
        case .merged: return 6
        case .witnessPing: return 7
        case .info: return 8
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
    var isPinned: Bool = false
    var isArchived: Bool = false
    var priority: Int = 2  // 0=urgent, 1=high, 2=normal, 3=low, 4=backlog
    var threadId: String?  // Groups messages in threads via reply-to chain
    var replyTo: UUID?     // ID of the message this is a reply to
}

/// Read status filter for mail messages.
enum MailReadStatus: String, CaseIterable {
    case unread
    case read
    case all
}

/// Combined filter state for the Mail Panel inbox.
struct MailFilter: Equatable {
    var sender: String?
    var rig: String?
    var priority: Int?
    var type: MailMessageType?
    var readStatus: MailReadStatus?

    static let empty = MailFilter()

    var isActive: Bool { self != .empty }
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

    // MARK: - Mail Panel Extensions

    /// Pinned standing orders, sorted by creation date (newest first).
    var pinnedMessages: [MailMessage] {
        messages.filter { $0.isPinned && !$0.isArchived }
    }

    /// Non-archived, non-pinned messages (the regular inbox).
    var inboxMessages: [MailMessage] {
        messages.filter { !$0.isPinned && !$0.isArchived }
    }

    /// Toggle pinned status of a message.
    func togglePinned(id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].isPinned.toggle()
    }

    /// Archive a message.
    func archive(id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].isArchived = true
    }

    /// Search messages by query across subject, body, and sender.
    func search(query: String) -> [MailMessage] {
        let q = query.lowercased()
        return messages.filter { msg in
            msg.subject.lowercased().contains(q) ||
            msg.body.lowercased().contains(q) ||
            msg.sender.lowercased().contains(q)
        }
    }

    /// Filter messages by the given criteria.
    func filtered(by filter: MailFilter) -> [MailMessage] {
        inboxMessages.filter { msg in
            if let sender = filter.sender, !msg.sender.lowercased().contains(sender.lowercased()) {
                return false
            }
            if let rig = filter.rig, !msg.sender.lowercased().contains(rig.lowercased()) {
                return false
            }
            if let priority = filter.priority, msg.priority != priority {
                return false
            }
            if let type = filter.type, msg.type != type {
                return false
            }
            if let readStatus = filter.readStatus {
                switch readStatus {
                case .unread: if msg.isRead { return false }
                case .read: if !msg.isRead { return false }
                case .all: break
                }
            }
            return true
        }
    }

    /// Get all messages in the same thread as the given message.
    func thread(for message: MailMessage) -> [MailMessage] {
        guard let threadId = message.threadId else { return [message] }
        return messages
            .filter { $0.threadId == threadId }
            .sorted { $0.createdAt < $1.createdAt }
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

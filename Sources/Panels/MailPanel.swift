import Foundation
import SwiftUI
import Combine

/// Load state for the Mail Panel.
enum MailPanelLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

/// Panel showing the Gas Town mail inbox with master-detail layout,
/// pinned standing orders, threading, compose, and search.
///
/// Uses ``MailInboxStore`` as the primary data source. Auto-refreshes
/// every 8s via `GasTownService.shared.$refreshTick`.
@MainActor
final class MailPanel: Panel, ObservableObject {
    let id: UUID
    let panelType: PanelType = .mailPanel

    @Published private(set) var displayTitle: String = String(localized: "mailPanel.title", defaultValue: "Mail")
    @Published private(set) var loadState: MailPanelLoadState = .idle
    @Published private(set) var focusFlashToken: Int = 0

    /// Action result toast (auto-dismisses after 4s).
    @Published var actionResult: GasTownActionResult?

    @Published var selectedMessageID: UUID?
    @Published var searchQuery: String = ""
    @Published var activeFilter: MailFilter = .empty
    @Published var isThreadView: Bool = false
    @Published var isComposePresented: Bool = false

    var displayIcon: String? { "envelope" }

    let workspaceId: UUID
    let mailStore: MailInboxStore = .shared

    /// Cached recipient directory for compose autocomplete.
    private(set) var recipientDirectory: [String] = []
    private var recipientCacheDate: Date?

    init(workspaceId: UUID) {
        self.id = UUID()
        self.workspaceId = workspaceId
    }

    // MARK: - Panel Protocol

    func focus() {}
    func unfocus() {}
    func close() {}

    func triggerFlash(reason: WorkspaceAttentionFlashReason) {
        _ = reason
        guard NotificationPaneFlashSettings.isEnabled() else { return }
        focusFlashToken += 1
    }

    // MARK: - Computed

    /// Filtered inbox messages (excludes pinned, applies search + filters).
    var filteredMessages: [MailMessage] {
        var result: [MailMessage]

        if !searchQuery.isEmpty {
            result = mailStore.search(query: searchQuery).filter { !$0.isPinned && !$0.isArchived }
        } else if activeFilter.isActive {
            result = mailStore.filtered(by: activeFilter)
        } else {
            result = mailStore.inboxMessages
        }

        return result
    }

    /// Pinned standing orders (always visible at top).
    var pinnedMessages: [MailMessage] {
        mailStore.pinnedMessages
    }

    /// Currently selected message.
    var selectedMessage: MailMessage? {
        guard let id = selectedMessageID else { return nil }
        return mailStore.messages.first { $0.id == id }
    }

    /// Thread for the currently selected message.
    var selectedThread: [MailMessage]? {
        guard let msg = selectedMessage else { return nil }
        let thread = mailStore.thread(for: msg)
        return thread.count > 1 ? thread : nil
    }

    // MARK: - Actions

    func selectMessage(_ id: UUID) {
        selectedMessageID = id
        mailStore.markRead(id: id)
    }

    func archiveMessage(_ id: UUID) {
        mailStore.archive(id: id)
        if selectedMessageID == id {
            selectedMessageID = nil
        }
    }

    func togglePin(_ id: UUID) {
        mailStore.togglePinned(id: id)
    }

    func deleteMessage(_ id: UUID) {
        mailStore.remove(id: id)
        if selectedMessageID == id {
            selectedMessageID = nil
        }
    }

    // MARK: - Refresh

    func refresh(silent: Bool = false) {
        if !silent {
            loadState = .loading
        }

        // MailInboxStore is the primary data source and is already populated
        // via socket push. We just signal loaded state.
        if loadState != .loaded {
            loadState = .loaded
        }
    }

    /// Refresh recipient directory for compose autocomplete.
    func refreshRecipientDirectory() {
        // Only refresh if cache is older than 60 seconds
        if let cacheDate = recipientCacheDate,
           Date().timeIntervalSince(cacheDate) < 60 {
            return
        }

        let townRoot = GasTownService.shared.townRoot?.path

        Task {
            let result = await GastownCommandRunner.gt(
                ["mail", "directory"],
                townRootPath: townRoot
            )

            let lines = result.stdout
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            self.recipientDirectory = lines
            self.recipientCacheDate = Date()
        }
    }

    /// Send a mail message via socket handler.
    func sendMail(
        to recipient: String,
        subject: String,
        body: String,
        pinned: Bool = false,
        replyTo: UUID? = nil
    ) {
        var params: [String: Any] = [
            "address": recipient,
            "subject": subject,
            "body": body,
        ]
        if pinned {
            params["pinned"] = true
        }
        if let replyId = replyTo {
            params["reply_to"] = replyId.uuidString
        }

        Task {
            let result = await GastownSocketHandlers.gastownMailSend(params: params)
            switch result {
            case .ok:
                showActionResult(.success(String(
                    localized: "mailPanel.action.sent",
                    defaultValue: "Mail sent to \(recipient)"
                )))
            case .err(_, let message):
                showActionResult(.failure(message))
            }
        }
    }

    // MARK: - Action Result Toast

    /// Show an action result toast that auto-dismisses after 4 seconds.
    func showActionResult(_ result: GasTownActionResult) {
        withAnimation(GasTownAnimation.statusChange) {
            actionResult = result
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.actionResult == result else { return }
            withAnimation(GasTownAnimation.statusChange) {
                self.actionResult = nil
            }
        }
    }
}

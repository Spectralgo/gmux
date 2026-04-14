import Foundation

// MARK: - Town Dashboard Adapter
//
// Aggregates data from multiple Gas Town CLI sources into a single
// snapshot for the Town Dashboard.
//
// Data sources:
//   - Agent roster: `gt status --json` (via AgentHealthAdapter)
//   - Bead counts: `bd list --json --all -n 0` (via GastownCommandRunner)
//   - Convoys: `gt convoy list --json` (via ConvoyAdapter)
//   - Activity: `git log --oneline -20` (v1 simple)

// MARK: - Domain Models

/// Snapshot of all dashboard data, loaded atomically.
struct TownDashboardSnapshot: Equatable, Sendable {
    let agents: [AgentHealthEntry]
    let attentionItems: [AttentionItem]
    let beadCounts: BeadCountSummary
    let activityFeed: [ActivityEntry]
}

/// An item that needs operator attention.
struct AttentionItem: Equatable, Sendable, Identifiable {
    let id: String
    let severity: AttentionSeverity
    let message: String
    let timestamp: Date?
    let actionLabel: String?
    let agentAddress: String?
}

enum AttentionSeverity: String, Equatable, Sendable, Comparable {
    case info
    case warning
    case critical

    static func < (lhs: AttentionSeverity, rhs: AttentionSeverity) -> Bool {
        let order: [AttentionSeverity] = [.info, .warning, .critical]
        return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }
}

/// Summary of bead counts by status.
struct BeadCountSummary: Equatable, Sendable {
    let ready: Int
    let inProgress: Int
    let closed: Int
}

/// A single entry in the activity feed.
struct ActivityEntry: Equatable, Sendable, Identifiable {
    let id: String
    let timestamp: String
    let message: String
    let agentName: String?
}

// MARK: - Error

enum TownDashboardAdapterError: Error, Equatable, Sendable {
    case cliNotFound(tool: String)
    case cliFailure(command: String, exitCode: Int32, stderr: String)
    case partialFailure(detail: String)
}

// MARK: - Load State

enum TownDashboardLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded(TownDashboardSnapshot)
    case failed(TownDashboardAdapterError)
}

// MARK: - Adapter

struct TownDashboardAdapter: Sendable {

    let agentAdapter: AgentHealthAdapter
    let convoyAdapter: ConvoyAdapter
    private let townRootPath: String?

    init(townRootPath: String? = nil) {
        self.townRootPath = townRootPath
        if let townRootPath {
            self.agentAdapter = AgentHealthAdapter(townRootPath: townRootPath)
            self.convoyAdapter = ConvoyAdapter(townRootPath: townRootPath)
        } else {
            self.agentAdapter = AgentHealthAdapter()
            self.convoyAdapter = ConvoyAdapter()
        }
    }

    /// Load dashboard snapshot from the socket adapter's cached Dolt data.
    ///
    /// This bypasses CLI subprocess calls entirely, reading from the
    /// centralized GasTownSocketAdapter which queries Dolt directly.
    /// Returns nil if socket adapter has no data (caller should fall back to CLI).
    @MainActor
    static func loadSnapshotFromSocket(_ adapter: GasTownSocketAdapter) -> TownDashboardSnapshot? {
        guard adapter.isConnected else { return nil }

        let agents = adapter.toAgentHealthEntries()
        let beadCounts = adapter.toBeadCountSummary()

        // Derive attention items from agents (convoys not yet mapped from Dolt)
        var attentionItems: [AttentionItem] = []
        for agent in agents {
            if !agent.isRunning && agent.hasWork {
                attentionItems.append(AttentionItem(
                    id: "stuck-\(agent.address)",
                    severity: .critical,
                    message: String(
                        localized: "dashboard.attention.agentStuck",
                        defaultValue: "\(agent.name) has hooked work but is not running"
                    ),
                    timestamp: nil,
                    actionLabel: String(localized: "dashboard.attention.nudge", defaultValue: "Nudge"),
                    agentAddress: agent.address
                ))
            }
        }
        attentionItems.sort { $0.severity > $1.severity }

        return TownDashboardSnapshot(
            agents: agents,
            attentionItems: attentionItems,
            beadCounts: beadCounts,
            activityFeed: []  // Activity feed still requires git log (not in Dolt)
        )
    }

    /// Load all dashboard data.
    func loadSnapshot() async -> Result<TownDashboardSnapshot, TownDashboardAdapterError> {
        // 1. Load agents
        let agents: [AgentHealthEntry]
        switch await agentAdapter.loadAgents() {
        case .success(let entries):
            agents = entries
        case .failure:
            agents = []
        }

        // 2. Load convoy data for attention items
        let convoys: [ConvoySummary]
        switch await convoyAdapter.loadActiveConvoys() {
        case .success(let summaries):
            convoys = summaries
        case .failure:
            convoys = []
        }

        // 3. Derive attention items
        let attentionItems = deriveAttentionItems(agents: agents, convoys: convoys)

        // 4. Load bead counts
        let beadCounts = await loadBeadCounts()

        // 5. Load activity feed
        let activityFeed = await loadActivityFeed()

        let snapshot = TownDashboardSnapshot(
            agents: agents,
            attentionItems: attentionItems,
            beadCounts: beadCounts,
            activityFeed: activityFeed
        )
        return .success(snapshot)
    }

    // MARK: - Attention Derivation

    private func deriveAttentionItems(
        agents: [AgentHealthEntry],
        convoys: [ConvoySummary]
    ) -> [AttentionItem] {
        var items: [AttentionItem] = []

        // Agent stuck: running + has work but idle is inferred from external signals
        // For now: agent not running but has work = stuck
        for agent in agents {
            if !agent.isRunning && agent.hasWork {
                items.append(AttentionItem(
                    id: "stuck-\(agent.address)",
                    severity: .critical,
                    message: String(
                        localized: "dashboard.attention.agentStuck",
                        defaultValue: "\(agent.name) has hooked work but is not running"
                    ),
                    timestamp: nil,
                    actionLabel: String(localized: "dashboard.attention.nudge", defaultValue: "Nudge"),
                    agentAddress: agent.address
                ))
            }

            // High unread mail
            if agent.unreadMail >= 3 {
                items.append(AttentionItem(
                    id: "mail-\(agent.address)",
                    severity: .warning,
                    message: String(
                        localized: "dashboard.attention.unreadMail",
                        defaultValue: "\(agent.name) has \(agent.unreadMail) unread messages"
                    ),
                    timestamp: nil,
                    actionLabel: nil,
                    agentAddress: agent.address
                ))
            }
        }

        // Stranded convoys
        for convoy in convoys where convoy.attention == .stranded {
            items.append(AttentionItem(
                id: "stranded-\(convoy.id)",
                severity: .warning,
                message: String(
                    localized: "dashboard.attention.strandedConvoy",
                    defaultValue: "Convoy \(convoy.id) has ready work but no assignees"
                ),
                timestamp: nil,
                actionLabel: String(localized: "dashboard.attention.feed", defaultValue: "Feed"),
                agentAddress: nil
            ))
        }

        // Blocked convoys
        for convoy in convoys where convoy.attention == .blocked {
            items.append(AttentionItem(
                id: "blocked-\(convoy.id)",
                severity: .critical,
                message: String(
                    localized: "dashboard.attention.blockedConvoy",
                    defaultValue: "Convoy \(convoy.id) is fully blocked"
                ),
                timestamp: nil,
                actionLabel: nil,
                agentAddress: nil
            ))
        }

        // Sort by severity (critical first)
        return items.sorted { $0.severity > $1.severity }
    }

    // MARK: - Bead Counts

    private func loadBeadCounts() async -> BeadCountSummary {
        let result = await GastownCommandRunner.bd(
            ["list", "--json", "--all", "-n", "0"],
            townRootPath: townRootPath
        )

        guard result.succeeded,
              let data = result.stdout.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return BeadCountSummary(ready: 0, inProgress: 0, closed: 0)
        }

        let internalTypes: Set<String> = [
            "wisp", "patrol", "gate", "molecule", "event", "heartbeat", "ping"
        ]

        var ready = 0
        var inProgress = 0
        var closed = 0

        for bead in array {
            let beadType = bead["type"] as? String ?? ""
            if internalTypes.contains(beadType) { continue }

            let status = bead["status"] as? String ?? ""
            switch status {
            case "open", "pinned":
                ready += 1
            case "in_progress", "hooked":
                inProgress += 1
            case "closed":
                closed += 1
            default:
                break
            }
        }

        return BeadCountSummary(ready: ready, inProgress: inProgress, closed: closed)
    }

    // MARK: - Activity Feed

    private func loadActivityFeed() async -> [ActivityEntry] {
        // V1: parse git log from the town root
        guard let townRootPath else { return [] }

        let result = await GastownCommandRunner.exec(
            "git",
            arguments: ["-C", townRootPath, "log", "--oneline", "--all", "-20",
                        "--format=%h %ar %s"]
        )

        guard result.succeeded else { return [] }

        let lines = result.stdout.components(separatedBy: "\n").filter { !$0.isEmpty }

        return lines.enumerated().compactMap { index, line in
            // Format: "<hash> <N unit(s) ago> <message>"
            // Split hash from rest
            guard let firstSpace = line.firstIndex(of: " ") else { return nil }
            let hash = String(line[line.startIndex..<firstSpace])
            let rest = String(line[line.index(after: firstSpace)...])

            // Split relative time (ends with " ago") from commit message
            let timestamp: String
            let message: String
            if let agoRange = rest.range(of: " ago ") {
                timestamp = String(rest[rest.startIndex...agoRange.lowerBound]) + "ago"
                message = String(rest[agoRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else if rest.hasSuffix(" ago") {
                timestamp = rest
                message = ""
            } else {
                timestamp = ""
                message = rest
            }

            let agentName = extractAgentName(from: message)

            return ActivityEntry(
                id: "git-\(hash)-\(index)",
                timestamp: timestamp,
                message: message,
                agentName: agentName
            )
        }
    }

    private func extractAgentName(from text: String) -> String? {
        let knownAgents = ["fury", "scavenger", "guzzle", "dust", "refinery", "witness", "mayor"]
        let lower = text.lowercased()
        return knownAgents.first { lower.contains($0) }
    }
}

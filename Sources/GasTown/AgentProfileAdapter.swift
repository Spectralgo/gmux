import Foundation

/// Snapshot of all data needed to render an agent profile.
struct AgentProfileSnapshot: Equatable, Sendable {
    let health: AgentHealthEntry?
    let beadHistory: [BeadSummary]
    let memories: [String]
}

/// Error type for agent profile loading.
enum AgentProfileAdapterError: Error, Equatable, Sendable {
    case cliNotFound(tool: String)
    case cliFailure(command: String, exitCode: Int32, stderr: String)
    case parseFailure(detail: String)

    var errorDescription: String {
        switch self {
        case .cliNotFound(let tool):
            return String(localized: "agentProfile.error.cliNotFound", defaultValue: "'\(tool)' CLI not found on PATH.")
        case .cliFailure(let cmd, let code, let stderr):
            return "\(cmd) exited \(code): \(stderr)"
        case .parseFailure(let detail):
            return detail
        }
    }
}

/// Load state for the agent profile panel.
enum AgentProfileLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded(AgentProfileSnapshot)
    case failed(AgentProfileAdapterError)
}

/// Adapter that fetches all data needed for an agent profile.
///
/// Composes AgentHealthAdapter with bead and memory CLI calls.
/// All methods are synchronous and must be called off-main.
struct AgentProfileAdapter: Sendable {
    private let townRootPath: String?
    private let agentAdapter: AgentHealthAdapter

    init(townRootPath: String? = nil) {
        self.townRootPath = townRootPath
        if let townRootPath {
            self.agentAdapter = AgentHealthAdapter(townRootPath: townRootPath)
        } else {
            self.agentAdapter = AgentHealthAdapter()
        }
    }

    /// Load the full profile snapshot for an agent.
    func loadProfile(agentAddress: String) -> Result<AgentProfileSnapshot, AgentProfileAdapterError> {
        // 1. Load health (from gt status --json)
        let healthEntry: AgentHealthEntry?
        switch agentAdapter.loadAgents() {
        case .success(let entries):
            healthEntry = entries.first { $0.address == agentAddress }
        case .failure:
            healthEntry = nil
        }

        // 2. Load bead history (from bd list --json --assignee <address>)
        let beadHistory = loadBeadHistory(assignee: agentAddress)

        // 3. Load memories (from gt memories <address>)
        let memories = loadMemories(agentAddress: agentAddress)

        return .success(AgentProfileSnapshot(
            health: healthEntry,
            beadHistory: beadHistory,
            memories: memories
        ))
    }

    /// Light refresh: only health data.
    func loadHealthOnly(agentAddress: String) -> AgentHealthEntry? {
        switch agentAdapter.loadAgents() {
        case .success(let entries):
            return entries.first { $0.address == agentAddress }
        case .failure:
            return nil
        }
    }

    // MARK: - Bead History

    private func loadBeadHistory(assignee: String) -> [BeadSummary] {
        guard let bdPath = GasTownCLIRunner.resolveBDCLI() else { return [] }

        let result = GasTownCLIRunner.runProcess(
            executablePath: bdPath,
            arguments: ["list", "--json", "--assignee", assignee],
            townRootPath: townRootPath
        )
        guard result.exitCode == 0 else { return [] }

        let output = String(data: result.stdout, encoding: .utf8) ?? ""
        return parseBeadListOutput(output)
    }

    private func parseBeadListOutput(_ output: String) -> [BeadSummary] {
        guard let data = output.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return array.compactMap { json -> BeadSummary? in
            guard let id = json["id"] as? String,
                  let title = json["title"] as? String else { return nil }

            return BeadSummary(
                id: id,
                title: title,
                status: json["status"] as? String ?? "open",
                priority: json["priority"] as? Int ?? 0,
                issueType: json["type"] as? String ?? "task",
                assignee: json["assignee"] as? String,
                owner: json["owner"] as? String,
                createdAt: json["created_at"] as? String,
                labels: json["labels"] as? [String] ?? [],
                dependencyCount: json["dependency_count"] as? Int ?? 0,
                dependentCount: json["dependent_count"] as? Int ?? 0
            )
        }
    }

    // MARK: - Memories

    private func loadMemories(agentAddress: String) -> [String] {
        guard let gtPath = GasTownCLIRunner.resolveGTCLI() else { return [] }

        let result = GasTownCLIRunner.runProcess(
            executablePath: gtPath,
            arguments: ["remember", "--list", agentAddress],
            townRootPath: townRootPath
        )
        guard result.exitCode == 0 else { return [] }

        let output = String(data: result.stdout, encoding: .utf8) ?? ""
        return output
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

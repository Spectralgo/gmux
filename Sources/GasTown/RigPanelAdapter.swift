import Foundation

// MARK: - Rig Panel Adapter
//
// Stateless adapter that composes data from RigInventoryAdapter,
// AgentHealthAdapter, ConvoyAdapter, and TownDashboardAdapter into a
// single RigPanelSnapshot. Same value-oriented pattern as
// TownDashboardAdapter.
//
// All methods are async — callers use Task {} for background execution.

// MARK: - Domain Models

/// Atomic snapshot of all data needed by the Rig Panel.
struct RigPanelSnapshot: Equatable, Sendable {
    let rig: Rig
    let agents: [AgentHealthEntry]
    let beadCounts: BeadCountSummary
    let convoys: [ConvoySummary]
    let healthIndicators: RigHealthIndicators
}

// MARK: - Error

enum RigPanelAdapterError: Error, Equatable, Sendable {
    case rigNotFound(rigId: String)
    case townRootNotAvailable
    case cliNotFound(tool: String)
}

// MARK: - Load State

enum RigPanelLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded(RigPanelSnapshot)
    case failed(RigPanelAdapterError)
}

// MARK: - Adapter

struct RigPanelAdapter: Sendable {

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

    /// Load all rig panel data for the given rig.
    func loadSnapshot(rigId: String) async -> Result<RigPanelSnapshot, RigPanelAdapterError> {
        guard let townRootPath else {
            return .failure(.townRootNotAvailable)
        }

        // Discover rig via inventory
        let townRoot = GasTownRoot(path: URL(fileURLWithPath: townRootPath))
        let inventory = RigInventoryAdapter.discover(town: townRoot)
        guard let rig = inventory.rigs.first(where: { $0.id == rigId }) else {
            return .failure(.rigNotFound(rigId: rigId))
        }

        // Load agents, filtered to this rig
        var agents: [AgentHealthEntry]
        switch await agentAdapter.loadAgents() {
        case .success(let all):
            agents = all.filter { $0.rig == rigId }
        case .failure:
            agents = []
        }

        // Resolve bead titles for agents with hook beads
        await resolveBeadTitles(agents: &agents)

        // Load convoys, filtered to this rig
        let convoys: [ConvoySummary]
        switch await convoyAdapter.loadActiveConvoys() {
        case .success(let all):
            convoys = all.filter { $0.rigIds.contains(rigId) }
        case .failure:
            convoys = []
        }

        // Load bead counts filtered by rig prefix
        let beadCounts = await loadBeadCounts(prefix: rig.config.beads.prefix)

        // Load health indicators
        let health = await loadHealthIndicators(rig: rig)

        let snapshot = RigPanelSnapshot(
            rig: rig,
            agents: agents,
            beadCounts: beadCounts,
            convoys: convoys,
            healthIndicators: health
        )
        return .success(snapshot)
    }

    /// Load a lightweight snapshot without health indicators (for fast refresh).
    func loadLightSnapshot(rigId: String) async -> Result<RigPanelSnapshot, RigPanelAdapterError> {
        guard let townRootPath else {
            return .failure(.townRootNotAvailable)
        }

        let townRoot = GasTownRoot(path: URL(fileURLWithPath: townRootPath))
        let inventory = RigInventoryAdapter.discover(town: townRoot)
        guard let rig = inventory.rigs.first(where: { $0.id == rigId }) else {
            return .failure(.rigNotFound(rigId: rigId))
        }

        var agents: [AgentHealthEntry]
        switch await agentAdapter.loadAgents() {
        case .success(let all):
            agents = all.filter { $0.rig == rigId }
        case .failure:
            agents = []
        }

        // Resolve bead titles for agents with hook beads
        await resolveBeadTitles(agents: &agents)

        let convoys: [ConvoySummary]
        switch await convoyAdapter.loadActiveConvoys() {
        case .success(let all):
            convoys = all.filter { $0.rigIds.contains(rigId) }
        case .failure:
            convoys = []
        }

        let beadCounts = await loadBeadCounts(prefix: rig.config.beads.prefix)

        // Lightweight: skip health indicators
        let health = RigHealthIndicators(
            build: .unknown(String(localized: "rigPanel.health.notChecked", defaultValue: "not checked")),
            ci: .unknown(String(localized: "rigPanel.health.notChecked", defaultValue: "not checked")),
            dolt: .unknown(String(localized: "rigPanel.health.notChecked", defaultValue: "not checked")),
            disk: .unknown(String(localized: "rigPanel.health.notChecked", defaultValue: "not checked")),
            doctor: DoctorSummary(passCount: 0, warnCount: 0, failCount: 0, details: [])
        )

        let snapshot = RigPanelSnapshot(
            rig: rig,
            agents: agents,
            beadCounts: beadCounts,
            convoys: convoys,
            healthIndicators: health
        )
        return .success(snapshot)
    }

    // MARK: - Bead Title Resolution

    /// Resolve bead titles for agents that have a hook bead ID.
    /// Calls `bd show <id> --json` for each unique bead ID and caches results.
    private func resolveBeadTitles(agents: inout [AgentHealthEntry]) async {
        // Collect unique bead IDs
        var beadIds: Set<String> = []
        for agent in agents {
            if let task = agent.currentTask { beadIds.insert(task) }
        }
        guard !beadIds.isEmpty else { return }

        // Resolve each bead ID → title
        var titleCache: [String: String] = [:]
        for beadId in beadIds {
            let result = await GastownCommandRunner.bd(
                ["show", beadId, "--json"],
                townRootPath: townRootPath
            )
            guard result.succeeded,
                  let data = result.stdout.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let title = json["title"] as? String
            else { continue }
            titleCache[beadId] = title
        }

        // Apply resolved titles
        for i in agents.indices {
            if let task = agents[i].currentTask, let title = titleCache[task] {
                agents[i].hookBeadTitle = title
            }
        }
    }

    // MARK: - Bead Counts (filtered by prefix)

    private func loadBeadCounts(prefix: String) async -> BeadCountSummary {
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

            let beadId = bead["id"] as? String ?? ""
            guard beadId.hasPrefix(prefix) else { continue }

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

    // MARK: - Health Indicators

    private func loadHealthIndicators(rig: Rig) async -> RigHealthIndicators {
        let build = await loadBuildStatus(rig: rig)
        let ci = await loadCIStatus(rig: rig)
        let dolt = await loadDoltStatus()
        let disk = loadDiskStatus(rig: rig)
        let doctor = await loadDoctorSummary(rigId: rig.id)

        return RigHealthIndicators(
            build: build,
            ci: ci,
            dolt: dolt,
            disk: disk,
            doctor: doctor
        )
    }

    private func loadBuildStatus(rig: Rig) async -> HealthSignal {
        // Get last commit info from the rig's repo
        let gitURL = rig.config.git_url
        guard !gitURL.isEmpty else {
            return .unknown(String(localized: "rigPanel.health.noGitUrl", defaultValue: "no git URL configured"))
        }

        let gitResult = await GastownCommandRunner.exec(
            "git",
            arguments: ["-C", rig.path.path, "log", "-1", "--format=%H %ar"]
        )

        guard gitResult.succeeded else {
            return .unknown(String(localized: "rigPanel.health.notARepo", defaultValue: "not a git repository"))
        }

        let output = gitResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = output.components(separatedBy: " ")
        let shortHash = parts.first.map { String($0.prefix(7)) } ?? "unknown"
        let relativeTime = parts.dropFirst().joined(separator: " ")

        // Try gh for CI status
        let ghResult = await GastownCommandRunner.exec(
            "gh",
            arguments: ["run", "list", "--repo", gitURL, "--limit", "1", "--json", "status,conclusion"],
            townRootPath: townRootPath
        )

        if ghResult.succeeded,
           let data = ghResult.stdout.data(using: .utf8),
           let runs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let latest = runs.first {
            let conclusion = latest["conclusion"] as? String ?? ""
            let status = latest["status"] as? String ?? ""

            if conclusion == "success" {
                return .green(String(
                    localized: "rigPanel.health.buildPassing",
                    defaultValue: "passing (\(shortHash), \(relativeTime))"
                ))
            } else if status == "in_progress" || status == "queued" {
                return .amber(String(
                    localized: "rigPanel.health.buildRunning",
                    defaultValue: "running (\(shortHash), \(relativeTime))"
                ))
            } else if conclusion == "failure" {
                return .red(String(
                    localized: "rigPanel.health.buildFailing",
                    defaultValue: "failing (\(shortHash), \(relativeTime))"
                ))
            }
        }

        // Fallback: just show last commit
        return .green(String(
            localized: "rigPanel.health.buildLastCommit",
            defaultValue: "\(shortHash) (\(relativeTime))"
        ))
    }

    private func loadCIStatus(rig: Rig) async -> HealthSignal {
        let gitURL = rig.config.git_url
        guard !gitURL.isEmpty else {
            return .unknown(String(localized: "rigPanel.health.ciNotAvailable", defaultValue: "not available"))
        }

        let result = await GastownCommandRunner.exec(
            "gh",
            arguments: ["run", "list", "--repo", gitURL, "--limit", "5", "--json", "status,conclusion,name"],
            townRootPath: townRootPath
        )

        guard result.succeeded,
              let data = result.stdout.data(using: .utf8),
              let runs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return .unknown(String(localized: "rigPanel.health.ciNotAvailable", defaultValue: "not available"))
        }

        let total = runs.count
        let passing = runs.filter { ($0["conclusion"] as? String) == "success" }.count
        let failing = runs.filter { ($0["conclusion"] as? String) == "failure" }.count

        if failing > 0 {
            return .red(String(
                localized: "rigPanel.health.ciSomeFailing",
                defaultValue: "\(passing)/\(total) workflows passing"
            ))
        } else if passing == total && total > 0 {
            return .green(String(
                localized: "rigPanel.health.ciAllPassing",
                defaultValue: "\(passing)/\(total) workflows passing"
            ))
        } else {
            return .amber(String(
                localized: "rigPanel.health.ciMixed",
                defaultValue: "\(passing)/\(total) workflows passing"
            ))
        }
    }

    private func loadDoltStatus() async -> HealthSignal {
        let result = await GastownCommandRunner.gt(
            ["dolt", "status"],
            townRootPath: townRootPath
        )

        if result.succeeded {
            let output = result.stdout.lowercased()
            if output.contains("healthy") || output.contains("ok") {
                return .green(String(localized: "rigPanel.health.doltHealthy", defaultValue: "healthy"))
            }
            return .green(String(localized: "rigPanel.health.doltConnected", defaultValue: "connected"))
        } else {
            if result.stderr.contains("connection refused") || result.stderr.contains("timeout") {
                return .red(String(localized: "rigPanel.health.doltUnreachable", defaultValue: "unreachable"))
            }
            return .amber(String(localized: "rigPanel.health.doltDegraded", defaultValue: "degraded"))
        }
    }

    private func loadDiskStatus(rig: Rig) -> HealthSignal {
        let fm = FileManager.default
        let rigPath = rig.path.path

        do {
            let attrs = try fm.attributesOfFileSystem(forPath: rigPath)
            if let freeBytes = attrs[.systemFreeSize] as? Int64 {
                let freeGB = Double(freeBytes) / 1_073_741_824.0
                let freeGBFormatted = String(format: "%.0f", freeGB)
                if freeGB < 5 {
                    return .red(String(
                        localized: "rigPanel.health.diskCritical",
                        defaultValue: "\(freeGBFormatted) GB free"
                    ))
                } else if freeGB < 20 {
                    return .amber(String(
                        localized: "rigPanel.health.diskLow",
                        defaultValue: "\(freeGBFormatted) GB free"
                    ))
                } else {
                    return .green(String(
                        localized: "rigPanel.health.diskOk",
                        defaultValue: "\(freeGBFormatted) GB free"
                    ))
                }
            }
        } catch {
            // Fall through to unknown
        }

        return .unknown(String(localized: "rigPanel.health.diskUnknown", defaultValue: "unknown"))
    }

    private func loadDoctorSummary(rigId: String) async -> DoctorSummary {
        let result = await GastownCommandRunner.gt(
            ["doctor", "--json", "--rig", rigId],
            townRootPath: townRootPath
        )

        guard (result.exitCode == 0 || result.exitCode == 1),
              let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return DoctorSummary(passCount: 0, warnCount: 0, failCount: 0, details: [])
        }

        var details: [DoctorCheckResult] = []
        if let checks = json["checks"] as? [[String: Any]] {
            for check in checks {
                let name = check["name"] as? String ?? "unknown"
                let statusStr = check["status"] as? String ?? "unknown"
                let message = check["message"] as? String ?? ""
                let status: DoctorCheckStatus
                switch statusStr.lowercased() {
                case "pass", "ok": status = .pass
                case "warn", "warning": status = .warn
                case "fail", "error", "critical": status = .fail
                default: status = .warn
                }
                details.append(DoctorCheckResult(name: name, status: status, message: message))
            }
        }

        let passCount = details.filter { $0.status == .pass }.count
        let warnCount = details.filter { $0.status == .warn }.count
        let failCount = details.filter { $0.status == .fail }.count

        return DoctorSummary(
            passCount: passCount,
            warnCount: warnCount,
            failCount: failCount,
            details: details
        )
    }
}

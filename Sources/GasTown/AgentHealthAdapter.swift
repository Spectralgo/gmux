import Foundation
import SwiftUI

// MARK: - Agent Health Adapter
//
// Read-only adapter over `gt status --json` for agent health data.
// Parses town-level agents and per-rig agents into a flat list
// that the AgentHealthPanel can display.
//
// Design: stateless, value-oriented — same pattern as ConvoyAdapter.

// MARK: - Domain Models

/// A single agent's health entry for the grid display.
struct AgentHealthEntry: Equatable, Sendable, Identifiable {
    var id: String { address }

    /// Agent name (e.g. "fury", "witness").
    let name: String
    /// Full address (e.g. "gmux/polecats/fury").
    let address: String
    /// Role (e.g. "polecat", "witness", "refinery", "coordinator").
    let role: String
    /// Rig name, or "town" for town-level agents.
    let rig: String
    /// Whether the agent's session is running.
    let isRunning: Bool
    /// Whether the agent has hooked work.
    let hasWork: Bool
    /// Number of unread mail messages.
    let unreadMail: Int
    /// Current task bead ID (e.g. "hq-29z"), if any.
    let currentTask: String?
    /// Context window usage percentage (0.0–1.0), if reported.
    let contextPercent: Double?
    /// How long the agent has been on current task (e.g. "45m"), if reported.
    let elapsed: String?
    /// Resolved bead title for the hook bead (e.g. "Fix polecat idle state").
    var hookBeadTitle: String?

    /// Whether this agent is a polecat (worker). Polecats have exactly 3 states:
    /// Working, Stalled, Zombie — they never "idle" because non-working polecats are nuked.
    var isPolecat: Bool {
        let r = role.lowercased()
        return r == "polecat" || r == "worker"
    }

    /// Role-aware status color. Polecats use Working/Stalled/Zombie semantics
    /// (never idle). Other roles keep the existing Running/Idle model.
    var statusColor: Color {
        if isPolecat {
            if isRunning && hasWork { return GasTownColors.active }      // Working
            if !isRunning && hasWork { return GasTownColors.stalled }    // Stalled (amber)
            // Polecat with no work shouldn't exist — show as zombie (red)
            return GasTownColors.error
        }
        // Non-polecat roles
        if !isRunning && hasWork { return GasTownColors.error }
        if isRunning { return GasTownColors.active }
        return GasTownColors.idle
    }

    /// Role-aware status label. Polecats use Working/Stalled/Zombie semantics.
    var statusLabel: String {
        if isPolecat {
            if isRunning && hasWork {
                return String(localized: "agent.status.working", defaultValue: "working")
            }
            if !isRunning && hasWork {
                return String(localized: "agent.status.stalled", defaultValue: "stalled")
            }
            return String(localized: "agent.status.zombie", defaultValue: "zombie")
        }
        // Non-polecat roles
        if !isRunning && hasWork {
            return String(localized: "agent.status.stuck", defaultValue: "stuck")
        }
        if isRunning && hasWork {
            return String(localized: "agent.status.working", defaultValue: "working")
        }
        if isRunning {
            return String(localized: "agent.status.running", defaultValue: "running")
        }
        return String(localized: "agent.status.idle", defaultValue: "idle")
    }
}

// MARK: - Error

enum AgentHealthAdapterError: Error, Equatable, Sendable {
    case gtCLINotFound
    case cliFailure(command: String, exitCode: Int32, stderr: String)
    case parseFailure(detail: String)
}

// MARK: - Load State

enum AgentHealthLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded([AgentHealthEntry])
    case failed(AgentHealthAdapterError)
}

// MARK: - Adapter

struct AgentHealthAdapter: Sendable {
    struct Environment: Sendable {
        let whichGT: @Sendable () -> String?
        let runCLI: @Sendable (_ path: String, _ args: [String]) -> GasTownCLIRunner.CLIResult

        static let live = Environment(
            whichGT: { GasTownCLIRunner.resolveGTCLI() },
            runCLI: { path, args in
                GasTownCLIRunner.runProcess(executablePath: path, arguments: args)
            }
        )
    }

    let environment: Environment

    init(environment: Environment = .live) {
        self.environment = environment
    }

    /// Convenience initializer that wires a known town root path into
    /// the CLI environment so child processes get GT_TOWN_ROOT and BEADS_DIR
    /// even when running inside a GUI app (where env vars are not inherited).
    init(townRootPath: String) {
        self.environment = Environment(
            whichGT: { GasTownCLIRunner.resolveGTCLI() },
            runCLI: { path, args in
                GasTownCLIRunner.runProcess(
                    executablePath: path,
                    arguments: args,
                    townRootPath: townRootPath
                )
            }
        )
    }

    /// Load all agents from `gt status --json`.
    func loadAgents() -> Result<[AgentHealthEntry], AgentHealthAdapterError> {
        guard let gtPath = environment.whichGT() else {
            return .failure(.gtCLINotFound)
        }

        let result = environment.runCLI(gtPath, ["status", "--json"])
        guard result.exitCode == 0 else {
            let stderr = String(data: result.stderr, encoding: .utf8) ?? ""
            return .failure(.cliFailure(
                command: "gt status --json",
                exitCode: result.exitCode,
                stderr: stderr
            ))
        }

        do {
            guard let json = try JSONSerialization.jsonObject(with: result.stdout) as? [String: Any] else {
                return .failure(.parseFailure(detail: "Root is not a JSON object"))
            }
            var entries: [AgentHealthEntry] = []

            // Town-level agents (mayor, deacon, etc.)
            if let agents = json["agents"] as? [[String: Any]] {
                for agent in agents {
                    if let entry = parseAgent(agent, rig: "town") {
                        entries.append(entry)
                    }
                }
            }

            // Rig-level agents
            if let rigs = json["rigs"] as? [[String: Any]] {
                for rig in rigs {
                    let rigName = rig["name"] as? String ?? "unknown"
                    if let agents = rig["agents"] as? [[String: Any]] {
                        for agent in agents {
                            if let entry = parseAgent(agent, rig: rigName) {
                                entries.append(entry)
                            }
                        }
                    }
                }
            }

            return .success(entries)
        } catch {
            return .failure(.parseFailure(detail: error.localizedDescription))
        }
    }

    // MARK: - Parsing

    private func parseAgent(_ json: [String: Any], rig: String) -> AgentHealthEntry? {
        guard let name = json["name"] as? String else { return nil }
        let address = json["address"] as? String ?? "\(rig)/\(name)"
        let role = json["role"] as? String ?? "unknown"
        let isRunning = json["running"] as? Bool ?? false
        let hasWork = json["has_work"] as? Bool ?? false
        let unreadMail = json["unread_mail"] as? Int ?? 0
        let currentTask = json["hook_bead"] as? String ?? json["current_task"] as? String
        let contextPercent = json["context_pct"] as? Double
        let elapsed = json["elapsed"] as? String

        return AgentHealthEntry(
            name: name,
            address: address,
            role: role,
            rig: rig,
            isRunning: isRunning,
            hasWork: hasWork,
            unreadMail: unreadMail,
            currentTask: currentTask,
            contextPercent: contextPercent,
            elapsed: elapsed,
            hookBeadTitle: nil
        )
    }

}

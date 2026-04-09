import Foundation

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
        let runCLI: @Sendable (_ path: String, _ args: [String]) -> CLIResult

        struct CLIResult: Sendable {
            let exitCode: Int32
            let stdout: Data
            let stderr: Data
        }

        static let live = Environment(
            whichGT: { GasTownDiscovery.resolveGTCLI() },
            runCLI: { path, args in
                let result = AgentHealthAdapter.runProcess(executablePath: path, arguments: args)
                return CLIResult(exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr)
            }
        )
    }

    let environment: Environment

    init(environment: Environment = .live) {
        self.environment = environment
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

        return AgentHealthEntry(
            name: name,
            address: address,
            role: role,
            rig: rig,
            isRunning: isRunning,
            hasWork: hasWork,
            unreadMail: unreadMail
        )
    }

    // MARK: - Process Runner

    private struct ProcessResult {
        let exitCode: Int32
        let stdout: Data
        let stderr: Data
    }

    private static func runProcess(executablePath: String, arguments: [String]) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return ProcessResult(exitCode: -1, stdout: Data(), stderr: Data())
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: stdoutData,
            stderr: stderrData
        )
    }
}

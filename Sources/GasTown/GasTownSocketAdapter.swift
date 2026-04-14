import Foundation
import Combine

// MARK: - Dolt Query Models
//
// Lightweight structs matching the Go daemon's gastown.go types.
// These represent raw Dolt data before conversion to existing
// domain models (AgentHealthEntry, ConvoySummary, etc.).

/// An agent wisp from the wisps table (role_type != '' OR agent_state != '').
struct GasTownDoltAgent: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let status: String
    let priority: Int
    let roleType: String
    let rig: String
    let agentState: String
    let hookBead: String
    let roleBead: String
    let lastActivity: String
    let assignee: String
    let database: String
}

/// An issue from the issues table.
struct GasTownDoltBead: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let status: String
    let priority: Int
    let issueType: String
    let assignee: String
    let createdAt: String
    let updatedAt: String
    let sender: String
    let pinned: Bool
    let wispType: String
    let database: String
}

/// A mail wisp from the wisps table (wisp_type = 'mail').
struct GasTownDoltMail: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let status: String
    let sender: String
    let target: String
    let pinned: Bool
    let createdAt: String
    let database: String
}

/// A convoy wisp from the wisps table (wisp_type = 'convoy').
struct GasTownDoltConvoy: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let status: String
    let priority: Int
    let molType: String
    let workType: String
    let createdAt: String
    let database: String
}

/// A key-value entry from config/metadata tables.
struct GasTownDoltDiagnostic: Equatable, Sendable, Identifiable {
    var id: String { "\(database).\(key)" }
    let key: String
    let value: String
    let database: String
}

// MARK: - Dolt Query Engine
//
// Executes SQL queries against the local Dolt server at 127.0.0.1:3307.
// Uses `dolt sql --host ... -r json` for clean JSON output, falling back
// to `mysql -e ... --json` if dolt is unavailable.

private enum DoltQueryEngine {

    private static let host = "127.0.0.1"
    private static let port = "3307"
    private static let user = "root"
    private static let timeout: TimeInterval = 10

    /// Run a SQL query against the Dolt server and return parsed rows.
    static func query(_ sql: String) async -> [[String: Any]]? {
        // Try dolt first, then mysql
        if let doltPath = GasTownCLIRunner.resolveExecutable("dolt") {
            return await queryViaDolt(doltPath: doltPath, sql: sql)
        }
        if let mysqlPath = GasTownCLIRunner.resolveExecutable("mysql") {
            return await queryViaMySQL(mysqlPath: mysqlPath, sql: sql)
        }
        return nil
    }

    /// Check if the Dolt server is reachable.
    static func ping() async -> Bool {
        let result = await query("SELECT 1 AS ok")
        return result != nil
    }

    // MARK: - Dolt SQL Client

    private static func queryViaDolt(doltPath: String, sql: String) async -> [[String: Any]]? {
        let result = await runProcess(
            executable: doltPath,
            arguments: ["sql", "-q", sql, "--host", host, "--port", port, "--user", user, "-r", "json"]
        )
        guard let result, result.exitCode == 0 else { return nil }
        return parseJSONRows(from: result.stdout)
    }

    // MARK: - MySQL Client Fallback

    private static func queryViaMySQL(mysqlPath: String, sql: String) async -> [[String: Any]]? {
        let result = await runProcess(
            executable: mysqlPath,
            arguments: ["-h", host, "-P", port, "-u", user, "-e", sql, "--batch", "--raw"]
        )
        guard let result, result.exitCode == 0 else { return nil }
        return parseTSVRows(from: result.stdout)
    }

    // MARK: - Process Runner

    private struct ProcessResult {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    private static func runProcess(executable: String, arguments: [String]) async -> ProcessResult? {
        await withCheckedContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.environment = GasTownCLIRunner.cliEnvironment()

            var timedOut = false
            let timeoutWork = DispatchWorkItem {
                timedOut = true
                process.terminate()
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            timeoutWork.cancel()

            if timedOut {
                continuation.resume(returning: nil)
                return
            }

            continuation.resume(returning: ProcessResult(
                stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                stderr: String(data: stderrData, encoding: .utf8) ?? "",
                exitCode: process.terminationStatus
            ))
        }
    }

    // MARK: - JSON Parsing

    private static func parseJSONRows(from text: String) -> [[String: Any]]? {
        guard let data = text.data(using: .utf8) else { return nil }

        // dolt sql -r json outputs: {"rows": [...]} or just [...]
        if let json = try? JSONSerialization.jsonObject(with: data) {
            if let dict = json as? [String: Any], let rows = dict["rows"] as? [[String: Any]] {
                return rows
            }
            if let rows = json as? [[String: Any]] {
                return rows
            }
        }
        return nil
    }

    // MARK: - TSV Parsing (mysql --batch fallback)

    private static func parseTSVRows(from text: String) -> [[String: Any]]? {
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count >= 2 else { return nil }

        let headers = lines[0].components(separatedBy: "\t")
        var rows: [[String: Any]] = []

        for line in lines.dropFirst() {
            let values = line.components(separatedBy: "\t")
            var row: [String: Any] = [:]
            for (i, header) in headers.enumerated() where i < values.count {
                let val = values[i]
                if val == "NULL" || val.isEmpty {
                    row[header] = ""
                } else if let intVal = Int(val) {
                    row[header] = intVal
                } else if val == "0" || val == "1" {
                    row[header] = val == "1"
                } else {
                    row[header] = val
                }
            }
            rows.append(row)
        }
        return rows
    }
}

// MARK: - GasTown Socket Adapter
//
// Centralized data hub that queries Dolt directly, replacing scattered
// CLI subprocess calls across individual adapters. Polls on a timer
// with change detection to minimize overhead.

@MainActor
final class GasTownSocketAdapter: ObservableObject {

    static let shared = GasTownSocketAdapter()

    // MARK: - Published Data

    @Published private(set) var agents: [GasTownDoltAgent] = []
    @Published private(set) var beads: [GasTownDoltBead] = []
    @Published private(set) var mail: [GasTownDoltMail] = []
    @Published private(set) var convoys: [GasTownDoltConvoy] = []
    @Published private(set) var diagnostics: [GasTownDoltDiagnostic] = []

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var lastError: String?

    // MARK: - Configuration

    /// Databases to query. Matches the Go daemon's allowedDatabases.
    let databases = ["hq", "gmux"]

    // MARK: - Internals

    private var watchTimer: Timer?
    private var refreshTask: Task<Void, Never>?

    /// Dolt table hashes for change detection (db.table -> hash).
    private var tableHashes: [String: String] = [:]

    // MARK: - Public API

    /// Refresh all data from Dolt.
    func refresh() async {
        // Check connectivity first
        let reachable = await DoltQueryEngine.ping()
        if !reachable {
            isConnected = false
            lastError = "Dolt server unreachable at 127.0.0.1:3307"
            return
        }
        isConnected = true
        lastError = nil

        // Fetch all data types concurrently
        async let agentsResult = fetchAgents()
        async let beadsResult = fetchBeads()
        async let mailResult = fetchMail()
        async let convoysResult = fetchConvoys()
        async let diagnosticsResult = fetchDiagnostics()

        let (a, b, m, c, d) = await (agentsResult, beadsResult, mailResult, convoysResult, diagnosticsResult)
        agents = a
        beads = b
        mail = m
        convoys = c
        diagnostics = d
        lastRefresh = Date()
    }

    /// Start polling Dolt on a 2-second timer.
    func startWatching() {
        stopWatching()
        // Immediate first refresh
        refreshTask = Task { await refresh() }
        watchTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshIfChanged()
            }
        }
    }

    /// Stop the polling timer.
    func stopWatching() {
        watchTimer?.invalidate()
        watchTimer = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Change Detection

    /// Only refresh if Dolt table hashes have changed.
    private func refreshIfChanged() async {
        let changed = await checkForChanges()
        if changed {
            await refresh()
        }
    }

    /// Check DOLT_HASHOF_TABLE for watched tables to detect changes.
    private func checkForChanges() async -> Bool {
        let watchedTables = ["issues", "wisps"]
        var anyChanged = false

        for db in databases {
            for table in watchedTables {
                let sql = "SELECT DOLT_HASHOF_TABLE('\(table)') AS hash FROM \(db).dual"
                // Simpler approach: query the hash directly
                let hashSQL = "SELECT DOLT_HASHOF_TABLE('\(table)') AS hash"
                let fullSQL = "USE `\(db)`; \(hashSQL)"

                guard let rows = await DoltQueryEngine.query(fullSQL),
                      let row = rows.first,
                      let hash = row["hash"] as? String else {
                    continue
                }

                let key = "\(db).\(table)"
                if let oldHash = tableHashes[key], oldHash != hash {
                    anyChanged = true
                }
                tableHashes[key] = hash
            }
        }
        return anyChanged
    }

    // MARK: - Data Fetching

    private func fetchAgents() async -> [GasTownDoltAgent] {
        var allAgents: [GasTownDoltAgent] = []
        for db in databases {
            let sql = """
                SELECT id, title, status, priority, role_type, rig, agent_state, \
                hook_bead, role_bead, last_activity, assignee \
                FROM `\(db)`.wisps \
                WHERE role_type != '' OR agent_state != ''
                """
            guard let rows = await DoltQueryEngine.query(sql) else { continue }
            for row in rows {
                allAgents.append(GasTownDoltAgent(
                    id: row["id"] as? String ?? "",
                    title: row["title"] as? String ?? "",
                    status: row["status"] as? String ?? "",
                    priority: asInt(row["priority"]),
                    roleType: row["role_type"] as? String ?? "",
                    rig: row["rig"] as? String ?? "",
                    agentState: row["agent_state"] as? String ?? "",
                    hookBead: row["hook_bead"] as? String ?? "",
                    roleBead: row["role_bead"] as? String ?? "",
                    lastActivity: row["last_activity"] as? String ?? "",
                    assignee: row["assignee"] as? String ?? "",
                    database: db
                ))
            }
        }
        return allAgents
    }

    private func fetchBeads() async -> [GasTownDoltBead] {
        var allBeads: [GasTownDoltBead] = []
        for db in databases {
            let sql = """
                SELECT id, title, status, priority, issue_type, assignee, \
                created_at, updated_at, sender, pinned, wisp_type \
                FROM `\(db)`.issues \
                ORDER BY updated_at DESC LIMIT 50
                """
            guard let rows = await DoltQueryEngine.query(sql) else { continue }
            for row in rows {
                allBeads.append(GasTownDoltBead(
                    id: row["id"] as? String ?? "",
                    title: row["title"] as? String ?? "",
                    status: row["status"] as? String ?? "",
                    priority: asInt(row["priority"]),
                    issueType: row["issue_type"] as? String ?? "",
                    assignee: row["assignee"] as? String ?? "",
                    createdAt: row["created_at"] as? String ?? "",
                    updatedAt: row["updated_at"] as? String ?? "",
                    sender: row["sender"] as? String ?? "",
                    pinned: asBool(row["pinned"]),
                    wispType: row["wisp_type"] as? String ?? "",
                    database: db
                ))
            }
        }
        return allBeads
    }

    private func fetchMail() async -> [GasTownDoltMail] {
        var allMail: [GasTownDoltMail] = []
        for db in databases {
            let sql = """
                SELECT id, title, status, sender, assignee, pinned, created_at \
                FROM `\(db)`.wisps \
                WHERE wisp_type = 'mail' \
                ORDER BY created_at DESC
                """
            guard let rows = await DoltQueryEngine.query(sql) else { continue }
            for row in rows {
                allMail.append(GasTownDoltMail(
                    id: row["id"] as? String ?? "",
                    title: row["title"] as? String ?? "",
                    status: row["status"] as? String ?? "",
                    sender: row["sender"] as? String ?? "",
                    target: row["assignee"] as? String ?? "",
                    pinned: asBool(row["pinned"]),
                    createdAt: row["created_at"] as? String ?? "",
                    database: db
                ))
            }
        }
        return allMail
    }

    private func fetchConvoys() async -> [GasTownDoltConvoy] {
        var allConvoys: [GasTownDoltConvoy] = []
        for db in databases {
            let sql = """
                SELECT id, title, status, priority, mol_type, work_type, created_at \
                FROM `\(db)`.wisps \
                WHERE wisp_type = 'convoy'
                """
            guard let rows = await DoltQueryEngine.query(sql) else { continue }
            for row in rows {
                allConvoys.append(GasTownDoltConvoy(
                    id: row["id"] as? String ?? "",
                    title: row["title"] as? String ?? "",
                    status: row["status"] as? String ?? "",
                    priority: asInt(row["priority"]),
                    molType: row["mol_type"] as? String ?? "",
                    workType: row["work_type"] as? String ?? "",
                    createdAt: row["created_at"] as? String ?? "",
                    database: db
                ))
            }
        }
        return allConvoys
    }

    private func fetchDiagnostics() async -> [GasTownDoltDiagnostic] {
        var allDiagnostics: [GasTownDoltDiagnostic] = []
        for db in databases {
            // Config table
            let configSQL = "SELECT `key`, `value` FROM `\(db)`.config"
            if let rows = await DoltQueryEngine.query(configSQL) {
                for row in rows {
                    allDiagnostics.append(GasTownDoltDiagnostic(
                        key: "config." + (row["key"] as? String ?? ""),
                        value: row["value"] as? String ?? "",
                        database: db
                    ))
                }
            }

            // Metadata table
            let metaSQL = "SELECT `key`, `value` FROM `\(db)`.metadata"
            if let rows = await DoltQueryEngine.query(metaSQL) {
                for row in rows {
                    allDiagnostics.append(GasTownDoltDiagnostic(
                        key: "metadata." + (row["key"] as? String ?? ""),
                        value: row["value"] as? String ?? "",
                        database: db
                    ))
                }
            }
        }
        return allDiagnostics
    }

    // MARK: - Domain Model Conversions

    /// Convert Dolt agents to AgentHealthEntry models for the agent health panel.
    func toAgentHealthEntries() -> [AgentHealthEntry] {
        agents.map { agent in
            let name = extractAgentName(from: agent)
            let address = agent.assignee.isEmpty
                ? "\(agent.rig)/\(name)"
                : agent.assignee

            return AgentHealthEntry(
                name: name,
                address: address,
                role: agent.roleType,
                rig: agent.rig.isEmpty ? agent.database : agent.rig,
                isRunning: !agent.agentState.isEmpty,
                hasWork: !agent.hookBead.isEmpty,
                unreadMail: 0,
                currentTask: agent.hookBead.isEmpty ? nil : agent.hookBead,
                contextPercent: nil,
                elapsed: nil,
                hookBeadTitle: nil
            )
        }
    }

    /// Convert Dolt beads to a summary of counts by status.
    func toBeadCountSummary() -> BeadCountSummary {
        let internalTypes: Set<String> = [
            "wisp", "patrol", "gate", "molecule", "event", "heartbeat", "ping"
        ]

        var ready = 0
        var inProgress = 0
        var closed = 0

        for bead in beads {
            if internalTypes.contains(bead.wispType) { continue }
            switch bead.status {
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

    // MARK: - Private Helpers

    private func extractAgentName(from agent: GasTownDoltAgent) -> String {
        // Try to extract name from title (often "polecat/name" or just "name")
        let title = agent.title
        if let lastSlash = title.lastIndex(of: "/") {
            return String(title[title.index(after: lastSlash)...])
        }
        // Try assignee address (e.g. "gmux/polecats/nitro" -> "nitro")
        if !agent.assignee.isEmpty {
            let components = agent.assignee.split(separator: "/")
            if let last = components.last {
                return String(last)
            }
        }
        return title.isEmpty ? agent.id : title
    }

    private func asInt(_ value: Any?) -> Int {
        if let i = value as? Int { return i }
        if let s = value as? String, let i = Int(s) { return i }
        return 0
    }

    private func asBool(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        if let i = value as? Int { return i != 0 }
        if let s = value as? String {
            return s == "1" || s.lowercased() == "true"
        }
        return false
    }
}

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
    let description: String
    let acceptanceCriteria: String
    let status: String
    let priority: Int
    let issueType: String
    let assignee: String
    let owner: String
    let createdAt: String
    let updatedAt: String
    let externalRef: String
    let sender: String
    let pinned: Bool
    let wispType: String
    let database: String
}

/// A mail wisp from the wisps table (wisp_type = 'mail').
struct GasTownDoltMail: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let body: String
    let status: String
    let issueType: String
    let sender: String
    let target: String
    let pinned: Bool
    let createdAt: String
    let database: String
}

/// A tracked issue inside a convoy.
struct GasTownDoltConvoyTrackedIssue: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let status: String
    let assignee: String?
    let rigId: String?
    let priority: Int
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
    let updatedAt: String
    let description: String
    let trackedIssues: [GasTownDoltConvoyTrackedIssue]
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
            arguments: [
                "--host", host,
                "--port", port,
                "--user", user,
                "--password", "",
                "--no-tls",
                "sql",
                "-q", sql,
                "-r", "json",
            ]
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
            if let dict = json as? [String: Any] {
                if let rows = dict["rows"] as? [[String: Any]] {
                    return rows
                }
                if dict.isEmpty {
                    return []
                }
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

    /// Databases to query. Updated from GasTownService discovery when available.
    private(set) var databases = ["hq", "gmux"]

    // MARK: - Internals

    private var watchTimer: Timer?
    private var refreshTask: Task<Void, Never>?

    /// Dolt table hashes for change detection (db.table -> hash).
    private var tableHashes: [String: String] = [:]

    // MARK: - Public API

    /// Update the Dolt databases queried by the adapter.
    func configureDatabases(_ names: [String]) {
        let unique = Array(Set(names.filter { !$0.isEmpty })).sorted()
        let configured = unique.isEmpty ? ["hq", "gmux"] : unique
        if databases != configured {
            databases = configured
            tableHashes.removeAll()
        }
    }

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
                let dbName = sqlIdentifier(db)
                let hashSQL = "SELECT DOLT_HASHOF_TABLE('\(table)') AS hash"
                let fullSQL = "USE \(dbName); \(hashSQL)"

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
            let dbName = sqlIdentifier(db)
            let sql = """
                SELECT id, title, status, priority, role_type, rig, agent_state, \
                hook_bead, role_bead, last_activity, assignee \
                FROM \(dbName).wisps \
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
            let dbName = sqlIdentifier(db)
            let sql = """
                SELECT id, title, description, acceptance_criteria, status, \
                priority, issue_type, assignee, owner, created_at, updated_at, \
                external_ref, sender, pinned, wisp_type \
                FROM \(dbName).issues \
                ORDER BY updated_at DESC LIMIT 50
                """
            guard let rows = await DoltQueryEngine.query(sql) else { continue }
            for row in rows {
                allBeads.append(GasTownDoltBead(
                    id: row["id"] as? String ?? "",
                    title: row["title"] as? String ?? "",
                    description: row["description"] as? String ?? "",
                    acceptanceCriteria: row["acceptance_criteria"] as? String ?? "",
                    status: row["status"] as? String ?? "",
                    priority: asInt(row["priority"]),
                    issueType: row["issue_type"] as? String ?? "",
                    assignee: row["assignee"] as? String ?? "",
                    owner: row["owner"] as? String ?? "",
                    createdAt: row["created_at"] as? String ?? "",
                    updatedAt: row["updated_at"] as? String ?? "",
                    externalRef: row["external_ref"] as? String ?? "",
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
            let dbName = sqlIdentifier(db)
            let sql = """
                SELECT id, title, description, status, issue_type, sender, \
                assignee, pinned, created_at \
                FROM \(dbName).issues \
                WHERE issue_type = 'message' OR wisp_type = 'mail' \
                ORDER BY created_at DESC
                """
            guard let rows = await DoltQueryEngine.query(sql) else { continue }
            for row in rows {
                allMail.append(GasTownDoltMail(
                    id: row["id"] as? String ?? "",
                    title: row["title"] as? String ?? "",
                    body: row["description"] as? String ?? "",
                    status: row["status"] as? String ?? "",
                    issueType: row["issue_type"] as? String ?? "",
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
            let dbName = sqlIdentifier(db)
            let sql = """
                SELECT id, title, description, status, priority, mol_type, \
                work_type, created_at, updated_at \
                FROM \(dbName).issues \
                WHERE issue_type = 'convoy' OR wisp_type = 'convoy' \
                ORDER BY updated_at DESC LIMIT 100
                """
            guard let rows = await DoltQueryEngine.query(sql) else { continue }
            for row in rows {
                let id = row["id"] as? String ?? ""
                let trackedIssues = await fetchTrackedIssues(convoyId: id, database: db)
                allConvoys.append(GasTownDoltConvoy(
                    id: id,
                    title: row["title"] as? String ?? "",
                    status: row["status"] as? String ?? "",
                    priority: asInt(row["priority"]),
                    molType: row["mol_type"] as? String ?? "",
                    workType: row["work_type"] as? String ?? "",
                    createdAt: row["created_at"] as? String ?? "",
                    updatedAt: row["updated_at"] as? String ?? "",
                    description: row["description"] as? String ?? "",
                    trackedIssues: trackedIssues,
                    database: db
                ))
            }
        }
        return allConvoys
    }

    private func fetchDiagnostics() async -> [GasTownDoltDiagnostic] {
        var allDiagnostics: [GasTownDoltDiagnostic] = []
        for db in databases {
            let dbName = sqlIdentifier(db)
            // Config table
            let configSQL = "SELECT `key`, `value` FROM \(dbName).config"
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
            let metaSQL = "SELECT `key`, `value` FROM \(dbName).metadata"
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

    private func fetchTrackedIssues(convoyId: String, database: String) async -> [GasTownDoltConvoyTrackedIssue] {
        guard !convoyId.isEmpty else { return [] }

        let dbName = sqlIdentifier(database)
        let id = sqlString(convoyId)
        let dependencySQL = """
            SELECT depends_on_id FROM \(dbName).dependencies \
            WHERE issue_id = '\(id)' AND type = 'tracks'
            """
        guard let dependencyRows = await DoltQueryEngine.query(dependencySQL) else { return [] }
        let trackedIds = dependencyRows.compactMap { $0["depends_on_id"] as? String }
        guard !trackedIds.isEmpty else { return [] }

        var issuesById: [String: GasTownDoltConvoyTrackedIssue] = [:]
        let normalizedIds = trackedIds.map(normalizeTrackedIssueId)
        for db in databases {
            let dbName = sqlIdentifier(db)
            let idList = normalizedIds
                .map { "'\(sqlString($0))'" }
                .joined(separator: ", ")
            guard !idList.isEmpty else { continue }
            let issuesSQL = """
                SELECT id, title, status, priority, assignee FROM \(dbName).issues \
                WHERE id IN (\(idList))
                """
            guard let issueRows = await DoltQueryEngine.query(issuesSQL) else { continue }
            for row in issueRows {
                let issueId = row["id"] as? String ?? ""
                issuesById[issueId] = GasTownDoltConvoyTrackedIssue(
                    id: issueId,
                    title: row["title"] as? String ?? issueId,
                    status: row["status"] as? String ?? "open",
                    assignee: emptyStringAsNil(row["assignee"] as? String),
                    rigId: db,
                    priority: asInt(row["priority"])
                )
            }
        }

        return trackedIds.map { rawId in
            let normalizedId = normalizeTrackedIssueId(rawId)
            return issuesById[normalizedId] ?? GasTownDoltConvoyTrackedIssue(
                id: normalizedId,
                title: normalizedId,
                status: "open",
                assignee: nil,
                rigId: nil,
                priority: 0
            )
        }
    }

    private func fetchBeadRow(id beadId: String) async -> GasTownDoltBead? {
        guard !beadId.isEmpty else { return nil }
        let escapedId = sqlString(beadId)
        for db in databases {
            let dbName = sqlIdentifier(db)
            let sql = """
                SELECT id, title, description, acceptance_criteria, status, \
                priority, issue_type, assignee, owner, created_at, updated_at, \
                external_ref, sender, pinned, wisp_type \
                FROM \(dbName).issues \
                WHERE id = '\(escapedId)' LIMIT 1
                """
            guard let rows = await DoltQueryEngine.query(sql),
                  let row = rows.first else { continue }
            return GasTownDoltBead(
                id: row["id"] as? String ?? beadId,
                title: row["title"] as? String ?? beadId,
                description: row["description"] as? String ?? "",
                acceptanceCriteria: row["acceptance_criteria"] as? String ?? "",
                status: row["status"] as? String ?? "open",
                priority: asInt(row["priority"]),
                issueType: row["issue_type"] as? String ?? "",
                assignee: row["assignee"] as? String ?? "",
                owner: row["owner"] as? String ?? "",
                createdAt: row["created_at"] as? String ?? "",
                updatedAt: row["updated_at"] as? String ?? "",
                externalRef: row["external_ref"] as? String ?? "",
                sender: row["sender"] as? String ?? "",
                pinned: asBool(row["pinned"]),
                wispType: row["wisp_type"] as? String ?? "",
                database: db
            )
        }
        return nil
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

    /// Convert cached Dolt convoys to Convoy Board summaries.
    func toConvoySummaries(includeClosed: Bool = false) -> [ConvoySummary] {
        convoys
            .filter { includeClosed || $0.status != "closed" }
            .map(convoySummary)
    }

    /// Load a single convoy detail via direct Dolt queries.
    func convoyDetail(id: String) async -> ConvoyDetail? {
        if let cached = convoys.first(where: { $0.id == id }) {
            return convoyDetail(cached)
        }

        guard let row = await fetchConvoyRow(id: id) else { return nil }
        return convoyDetail(row)
    }

    /// Convert cached persistent mail rows to MailMessage values.
    func toMailMessages() -> [MailMessage] {
        mail.map { row in
            let type = mailMessageType(title: row.title, body: row.body)
            return MailMessage(
                id: deterministicUUID(from: row.id),
                type: type,
                subject: row.title,
                body: row.body,
                sender: row.sender.isEmpty ? row.database : row.sender,
                provenance: MailProvenance(
                    beadId: row.id,
                    convoyId: nil,
                    polecatName: nil,
                    branch: nil,
                    workspaceId: nil
                ),
                createdAt: parseDoltDate(row.createdAt) ?? Date(),
                isRead: row.status == "closed",
                isPinned: row.pinned,
                isArchived: row.status == "closed",
                priority: 2,
                threadId: nil,
                replyTo: nil
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    /// Fetch a single bead detail via direct Dolt query.
    func fetchBeadDetail(id: String) async -> BeadDetail? {
        let bead: GasTownDoltBead?
        if let cachedBead = beads.first(where: { $0.id == id }) {
            bead = cachedBead
        } else {
            bead = await fetchBeadRow(id: id)
        }
        guard let bead else { return nil }
        let dependencies = await fetchDependencies(beadId: id)
        return beadDetail(from: bead, dependencies: dependencies)
    }

    /// Fetch bead summaries for an assignee via direct Dolt query.
    func fetchBeadSummaries(assignee: String) async -> [BeadSummary] {
        let escapedAssignee = sqlString(assignee)
        var summaries: [BeadSummary] = []
        for db in databases {
            let dbName = sqlIdentifier(db)
            let sql = """
                SELECT id, title, status, priority, issue_type, assignee, owner, created_at \
                FROM \(dbName).issues \
                WHERE assignee = '\(escapedAssignee)' \
                ORDER BY updated_at DESC LIMIT 30
                """
            guard let rows = await DoltQueryEngine.query(sql) else { continue }
            summaries.append(contentsOf: rows.compactMap(beadSummary))
        }
        return summaries
    }

    // MARK: - Private Helpers

    private func fetchConvoyRow(id convoyId: String) async -> GasTownDoltConvoy? {
        let escapedId = sqlString(convoyId)
        for db in databases {
            let dbName = sqlIdentifier(db)
            let sql = """
                SELECT id, title, description, status, priority, mol_type, \
                work_type, created_at, updated_at \
                FROM \(dbName).issues \
                WHERE id = '\(escapedId)' \
                AND (issue_type = 'convoy' OR wisp_type = 'convoy') \
                LIMIT 1
                """
            guard let rows = await DoltQueryEngine.query(sql),
                  let row = rows.first else { continue }
            let id = row["id"] as? String ?? convoyId
            return GasTownDoltConvoy(
                id: id,
                title: row["title"] as? String ?? id,
                status: row["status"] as? String ?? "open",
                priority: asInt(row["priority"]),
                molType: row["mol_type"] as? String ?? "",
                workType: row["work_type"] as? String ?? "",
                createdAt: row["created_at"] as? String ?? "",
                updatedAt: row["updated_at"] as? String ?? "",
                description: row["description"] as? String ?? "",
                trackedIssues: await fetchTrackedIssues(convoyId: id, database: db),
                database: db
            )
        }
        return nil
    }

    private func fetchDependencies(beadId: String) async -> [BeadDependency] {
        let escapedId = sqlString(beadId)
        var dependencies: [BeadDependency] = []
        for db in databases {
            let dbName = sqlIdentifier(db)
            let sql = """
                SELECT depends_on_id FROM \(dbName).dependencies \
                WHERE issue_id = '\(escapedId)'
                """
            guard let rows = await DoltQueryEngine.query(sql) else { continue }
            for row in rows {
                guard let dependencyId = row["depends_on_id"] as? String else { continue }
                let normalizedId = normalizeTrackedIssueId(dependencyId)
                let dependencyBead = await fetchBeadRow(id: normalizedId)
                dependencies.append(BeadDependency(
                    id: normalizedId,
                    title: dependencyBead?.title ?? normalizedId,
                    status: dependencyBead.flatMap { BeadStatus(rawValue: $0.status) }
                ))
            }
        }
        return dependencies
    }

    private func convoySummary(_ convoy: GasTownDoltConvoy) -> ConvoySummary {
        let tracked = convoy.trackedIssues
        let completed = tracked.filter { $0.status == "closed" }.count
        let polecats = assignedPolecats(from: tracked)
        let rigIds = Array(Set(tracked.compactMap(\.rigId))).sorted()

        return ConvoySummary(
            id: convoy.id,
            title: convoy.title,
            status: convoy.status,
            totalIssues: tracked.count,
            completedIssues: completed,
            attention: convoyAttention(status: convoy.status, trackedIssues: tracked),
            polecatDetails: polecats,
            rigIds: rigIds,
            createdAt: convoy.createdAt.isEmpty ? nil : convoy.createdAt,
            updatedAt: convoy.updatedAt.isEmpty ? nil : convoy.updatedAt
        )
    }

    private func convoyDetail(_ convoy: GasTownDoltConvoy) -> ConvoyDetail {
        let tracked = convoy.trackedIssues.map { issue in
            ConvoyTrackedIssue(
                id: issue.id,
                title: issue.title,
                status: issue.status,
                assignee: issue.assignee,
                rigId: issue.rigId,
                priority: issue.priority
            )
        }
        let rigIds = Array(Set(tracked.compactMap(\.rigId))).sorted()

        return ConvoyDetail(
            id: convoy.id,
            title: convoy.title,
            status: convoy.status,
            description: convoy.description.isEmpty ? nil : convoy.description,
            trackedIssues: tracked,
            attention: convoyAttention(status: convoy.status, trackedIssues: convoy.trackedIssues),
            rigIds: rigIds,
            createdAt: convoy.createdAt.isEmpty ? nil : convoy.createdAt,
            updatedAt: convoy.updatedAt.isEmpty ? nil : convoy.updatedAt
        )
    }

    private func beadDetail(from bead: GasTownDoltBead, dependencies: [BeadDependency]) -> BeadDetail {
        BeadDetail(
            id: bead.id,
            title: bead.title,
            status: BeadStatus(rawValue: bead.status) ?? .open,
            priority: bead.priority,
            type: bead.issueType.isEmpty ? nil : bead.issueType,
            owner: bead.owner.isEmpty ? nil : bead.owner,
            assignee: bead.assignee.isEmpty ? nil : bead.assignee,
            description: bead.description,
            acceptanceCriteria: splitMultiline(bead.acceptanceCriteria),
            dependencies: dependencies,
            createdDate: bead.createdAt.isEmpty ? nil : bead.createdAt,
            updatedDate: bead.updatedAt.isEmpty ? nil : bead.updatedAt,
            externalRef: bead.externalRef.isEmpty ? nil : bead.externalRef
        )
    }

    private func beadSummary(_ row: [String: Any]) -> BeadSummary? {
        guard let id = row["id"] as? String,
              let title = row["title"] as? String else { return nil }
        return BeadSummary(
            id: id,
            title: title,
            status: row["status"] as? String ?? "open",
            priority: asInt(row["priority"]),
            issueType: row["issue_type"] as? String ?? "task",
            assignee: emptyStringAsNil(row["assignee"] as? String),
            owner: emptyStringAsNil(row["owner"] as? String),
            createdAt: emptyStringAsNil(row["created_at"] as? String),
            labels: [],
            dependencyCount: 0,
            dependentCount: 0
        )
    }

    private func convoyAttention(
        status: String,
        trackedIssues: [GasTownDoltConvoyTrackedIssue]
    ) -> ConvoyAttentionState {
        if status == "closed" { return .normal }
        let openIssues = trackedIssues.filter { $0.status != "closed" }
        guard !openIssues.isEmpty else { return .normal }
        let blocked = openIssues.filter { $0.status == "blocked" }
        if blocked.count == openIssues.count { return .blocked }
        let unblocked = openIssues.filter { $0.status != "blocked" }
        let hasAssignedWork = unblocked.contains { issue in
            guard let assignee = issue.assignee else { return false }
            return assignee.contains("/polecats/")
        }
        return !unblocked.isEmpty && !hasAssignedWork ? .stranded : .normal
    }

    private func assignedPolecats(from issues: [GasTownDoltConvoyTrackedIssue]) -> [AssignedPolecat] {
        var seen: Set<String> = []
        var polecats: [AssignedPolecat] = []
        for issue in issues {
            guard let assignee = issue.assignee,
                  assignee.contains("/polecats/"),
                  !seen.contains(assignee) else { continue }
            seen.insert(assignee)
            let name = assignee.split(separator: "/").last.map(String.init) ?? assignee
            let status: PolecatSwarmStatus = switch issue.status {
            case "blocked": .stalled
            case "in_progress", "hooked", "open": .working
            default: .zombie
            }
            polecats.append(AssignedPolecat(name: name, address: assignee, status: status))
        }
        return polecats
    }

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

    private func normalizeTrackedIssueId(_ id: String) -> String {
        if id.hasPrefix("external:") {
            return id.split(separator: ":").last.map(String.init) ?? id
        }
        return id
    }

    private func sqlIdentifier(_ value: String) -> String {
        "`" + value.replacingOccurrences(of: "`", with: "``") + "`"
    }

    private func sqlString(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private func splitMultiline(_ value: String) -> [String] {
        value.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func emptyStringAsNil(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func mailMessageType(title: String, body: String) -> MailMessageType {
        let text = "\(title)\n\(body)".uppercased()
        if text.contains("MERGE_FAILED") { return .mergeFailed }
        if text.contains("REWORK_REQUEST") || text.contains("FIX_NEEDED") { return .reworkRequest }
        if text.contains("MERGE_READY") { return .mergeReady }
        if text.contains("POLECAT_DONE") { return .polecatDone }
        if text.contains("MERGED") { return .merged }
        if text.contains("HANDOFF") { return .handoff }
        if text.contains("WITNESS_PING") || text.contains("PATROL") { return .witnessPing }
        if text.contains("HELP") || text.contains("BLOCKED") { return .help }
        return .info
    }

    private func deterministicUUID(from value: String) -> UUID {
        var first: UInt64 = 0xcbf29ce484222325
        var second: UInt64 = 0x84222325cbf29ce4
        for byte in value.utf8 {
            first ^= UInt64(byte)
            first &*= 0x100000001b3
            second ^= UInt64(byte) &+ 0x9e3779b97f4a7c15
            second &*= 0x100000001b3
        }
        let bytes = (0..<16).map { index -> UInt8 in
            let source = index < 8 ? first : second
            let shift = UInt64((7 - (index % 8)) * 8)
            return UInt8((source >> shift) & 0xff)
        }
        return UUID(uuid: uuid_t(
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private func parseDoltDate(_ value: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: value)
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

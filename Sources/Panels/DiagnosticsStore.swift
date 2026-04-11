import Foundation
import Combine

/// Owns all diagnostics data for the Engine Room panel.
///
/// Runs a single 30-second polling timer that concurrently fetches from
/// `gt vitals --json`, `df`, `du`, and `tmux list-sessions`. Computes
/// traffic light status from the fetched data. Timer pauses when the panel
/// is not visible.
@MainActor
final class DiagnosticsStore: ObservableObject {

    // MARK: - Traffic Lights

    @Published private(set) var systemStatus: TrafficLight = .unknown
    @Published private(set) var agentsStatus: TrafficLight = .unknown
    @Published private(set) var storageStatus: TrafficLight = .unknown

    // MARK: - Detail Sections

    @Published private(set) var systemDetails: SystemDetails?
    @Published private(set) var agentsDetails: AgentsDetails?
    @Published private(set) var storageDetails: StorageDetails?

    // MARK: - Watchdog Chain

    @Published private(set) var watchdogChain: WatchdogChainState?

    // MARK: - Escalation Queue

    @Published private(set) var escalations: [EscalationEntry] = []

    // MARK: - Doctor

    @Published private(set) var doctorResult: DoctorResult?
    @Published private(set) var doctorFixLog: [DoctorFixEntry]?

    // MARK: - Plugins

    @Published private(set) var plugins: [PluginEntry] = []

    // MARK: - Event Timeline

    @Published private(set) var recentEvents: [EventEntry] = []

    // MARK: - Formulas

    @Published private(set) var formulaStatus: [FormulaEntry] = []

    // MARK: - Meta

    @Published private(set) var isRefreshing: Bool = false
    @Published private(set) var lastRefresh: Date?

    // MARK: - Polling

    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var eventStreamTask: Task<Void, Never>?

    /// Maximum number of events to keep in the ring buffer.
    private static let eventBufferSize = 50

    /// Start automatic polling at the given interval.
    func startPolling(interval: TimeInterval = 30) {
        stopPolling()
        // Immediate first refresh
        Task { await refreshNow() }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshNow()
            }
        }
        startEventStream()
    }

    /// Stop automatic polling.
    func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        refreshTask?.cancel()
        refreshTask = nil
        stopEventStream()
    }

    /// Trigger a single refresh cycle.
    func refreshNow() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            lastRefresh = Date()
        }

        await withTaskGroup(of: FetchResult.self) { group in
            group.addTask { await .vitals(Self.fetchVitals()) }
            group.addTask { await .disk(Self.fetchDiskUsage()) }
            group.addTask { await .derivedData(Self.fetchDerivedDataSize()) }
            group.addTask { await .buildCache(Self.fetchBuildCacheSize()) }
            group.addTask { await .tmux(Self.fetchTmuxSessions()) }
            group.addTask { await .deaconHeartbeat(Self.fetchDeaconHeartbeat()) }
            group.addTask { await .bootStatus(Self.fetchBootStatus()) }
            group.addTask { await .escalations(Self.fetchEscalations()) }
            group.addTask { await .formulas(Self.fetchFormulas()) }
            group.addTask { await .plugins(Self.fetchPlugins()) }

            for await result in group {
                switch result {
                case .vitals(let v):
                    applyVitals(v)
                case .disk(let d):
                    applyDisk(d)
                case .derivedData(let s):
                    applyDerivedData(s)
                case .buildCache(let s):
                    applyBuildCache(s)
                case .tmux(let t):
                    applyTmux(t)
                case .deaconHeartbeat(let h):
                    applyDeaconHeartbeat(h)
                case .bootStatus(let b):
                    applyBootStatus(b)
                case .escalations(let e):
                    applyEscalations(e)
                case .formulas(let f):
                    applyFormulas(f)
                case .plugins(let p):
                    applyPlugins(p)
                }
            }
        }

        recomputeTrafficLights()
    }

    // MARK: - Fetch Result Envelope

    private enum FetchResult: Sendable {
        case vitals(VitalsData?)
        case disk(DiskData?)
        case derivedData(UInt64?)
        case buildCache(UInt64?)
        case tmux(TmuxData?)
        case deaconHeartbeat(DeaconHeartbeatData?)
        case bootStatus(BootStatusData?)
        case escalations([EscalationEntry])
        case formulas([FormulaEntry])
        case plugins([PluginEntry])
    }

    // MARK: - Vitals Parsing

    struct VitalsData: Sendable {
        let doltServer: DoltServerInfo?
        let daemonPID: Int?
        let daemonRunning: Bool
        let bootWatchdogHealthy: Bool
        let deaconHeartbeatFresh: Bool
        let daemonTickInterval: TimeInterval
        let doltCommitGap: TimeInterval?
        let deadSessions: Int
        let zombieSessions: Int
        let orphanProcesses: Int
        let stuckPatrols: Int
        let sessionNames: [String]
        let activeSessions: Int
    }

    private static func fetchVitals() async -> VitalsData? {
        let result = await GastownCommandRunner.gt(["vitals", "--json"], timeoutSeconds: 15)
        guard result.succeeded,
              let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Parse dolt server info
        var doltServer: DoltServerInfo?
        if let dolt = json["dolt"] as? [String: Any] {
            let port = dolt["port"] as? Int ?? 3307
            let pid = dolt["pid"] as? Int ?? 0
            let memMB = dolt["memory_mb"] as? Double ?? 0
            let conns = dolt["connections"] as? Int ?? 0
            let maxConns = dolt["max_connections"] as? Int ?? 0
            if pid > 0 {
                doltServer = DoltServerInfo(port: port, pid: pid, memoryMB: memMB, connections: conns, maxConnections: maxConns)
            }
        }

        // Parse daemon info
        let daemon = json["daemon"] as? [String: Any]
        let daemonPID = daemon?["pid"] as? Int
        let daemonRunning = daemon?["running"] as? Bool ?? false

        // Parse watchdog
        let watchdog = json["watchdog"] as? [String: Any]
        let bootHealthy = watchdog?["healthy"] as? Bool ?? true

        // Parse daemon tick interval
        let tickInterval = daemon?["tick_interval"] as? TimeInterval ?? 180

        // Parse deacon heartbeat freshness from vitals
        let deacon = json["deacon"] as? [String: Any]
        let heartbeatFresh = deacon?["heartbeat_fresh"] as? Bool ?? true

        // Parse dolt commit gap
        let doltCommitGap = json["dolt_commit_gap"] as? TimeInterval
            ?? (json["dolt"] as? [String: Any])?["commit_gap_seconds"] as? TimeInterval

        // Parse sessions
        let sessions = json["sessions"] as? [String: Any]
        let activeSessions = sessions?["active"] as? Int ?? 0
        let deadSessions = sessions?["dead"] as? Int ?? 0
        let zombieSessions = sessions?["zombie"] as? Int ?? 0
        let orphanProcesses = sessions?["orphan_processes"] as? Int ?? 0
        let stuckPatrols = sessions?["stuck_patrols"] as? Int ?? 0
        let names = sessions?["names"] as? [String] ?? []

        return VitalsData(
            doltServer: doltServer,
            daemonPID: daemonPID,
            daemonRunning: daemonRunning,
            bootWatchdogHealthy: bootHealthy,
            deaconHeartbeatFresh: heartbeatFresh,
            daemonTickInterval: tickInterval,
            doltCommitGap: doltCommitGap,
            deadSessions: deadSessions,
            zombieSessions: zombieSessions,
            orphanProcesses: orphanProcesses,
            stuckPatrols: stuckPatrols,
            sessionNames: names,
            activeSessions: activeSessions
        )
    }

    // MARK: - Disk Usage

    struct DiskData: Sendable {
        let total: UInt64
        let free: UInt64
    }

    private static func fetchDiskUsage() async -> DiskData? {
        let output = await runShell("/bin/df", arguments: ["-k", "/"])
        guard let output else { return nil }
        // df -k output: Filesystem 1024-blocks Used Available ...
        let lines = output.components(separatedBy: "\n")
        guard lines.count >= 2 else { return nil }
        let parts = lines[1].split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 4 else { return nil }
        // parts[1] = total 1K blocks, parts[3] = available 1K blocks
        guard let totalKB = UInt64(parts[1]),
              let freeKB = UInt64(parts[3]) else { return nil }
        return DiskData(total: totalKB * 1024, free: freeKB * 1024)
    }

    // MARK: - DerivedData Size

    private static func fetchDerivedDataSize() async -> UInt64? {
        let home = NSHomeDirectory()
        let path = "\(home)/Library/Developer/Xcode/DerivedData"
        return await fetchDirectorySize(path)
    }

    // MARK: - Build Cache Size

    private static func fetchBuildCacheSize() async -> UInt64? {
        let output = await runShell("/usr/bin/du", arguments: ["-sk", "/tmp/cmux-*"])
        guard let output, !output.isEmpty else { return 0 }
        var total: UInt64 = 0
        for line in output.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.split(separator: "\t", maxSplits: 1)
            if let kb = UInt64(parts.first ?? "") {
                total += kb * 1024
            }
        }
        return total
    }

    // MARK: - Tmux Sessions

    struct TmuxData: Sendable {
        let sessionNames: [String]
    }

    private static func fetchTmuxSessions() async -> TmuxData? {
        let output = await runShell("/usr/bin/tmux", arguments: ["list-sessions", "-F", "#{session_name}"])
        guard let output else { return TmuxData(sessionNames: []) }
        let names = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        return TmuxData(sessionNames: names)
    }

    // MARK: - Apply Results

    private func applyVitals(_ data: VitalsData?) {
        guard let data else { return }
        let newSystem = SystemDetails(
            doltServer: data.doltServer,
            daemonPID: data.daemonPID,
            daemonRunning: data.daemonRunning,
            bootWatchdogHealthy: data.bootWatchdogHealthy,
            deaconHeartbeatFresh: data.deaconHeartbeatFresh,
            doltCommitGap: data.doltCommitGap
        )
        if systemDetails != newSystem {
            systemDetails = newSystem
        }

        let newAgents = AgentsDetails(
            activeSessions: data.activeSessions,
            deadSessions: data.deadSessions,
            orphanProcessCount: data.orphanProcesses,
            stuckPatrolCount: data.stuckPatrols,
            zombieSessionCount: data.zombieSessions,
            sessionNames: data.sessionNames
        )
        if agentsDetails != newAgents {
            agentsDetails = newAgents
        }

        // Build daemon state from vitals (boot/deacon filled by file reads)
        let daemonState = DaemonState(
            pid: data.daemonPID,
            running: data.daemonRunning,
            tickInterval: data.daemonTickInterval
        )
        let currentChain = watchdogChain
        let newChain = WatchdogChainState(
            daemon: daemonState,
            boot: currentChain?.boot ?? BootState(lastFireTime: nil, lastDecision: .unknown, lastReason: nil),
            deacon: currentChain?.deacon ?? DeaconState(sessionAlive: false, lastHeartbeat: nil, heartbeatAge: nil, patrolActive: false)
        )
        if watchdogChain != newChain {
            watchdogChain = newChain
        }
    }

    private func applyDisk(_ data: DiskData?) {
        guard let data else { return }
        let current = storageDetails
        let updated = StorageDetails(
            diskTotal: data.total,
            diskFree: data.free,
            derivedDataSize: current?.derivedDataSize,
            buildCacheSize: current?.buildCacheSize,
            doltDataSize: current?.doltDataSize
        )
        if storageDetails != updated {
            storageDetails = updated
        }
    }

    private func applyDerivedData(_ size: UInt64?) {
        let current = storageDetails ?? StorageDetails(diskTotal: 0, diskFree: 0, derivedDataSize: nil, buildCacheSize: nil, doltDataSize: nil)
        let updated = StorageDetails(
            diskTotal: current.diskTotal,
            diskFree: current.diskFree,
            derivedDataSize: size,
            buildCacheSize: current.buildCacheSize,
            doltDataSize: current.doltDataSize
        )
        if storageDetails != updated {
            storageDetails = updated
        }
    }

    private func applyBuildCache(_ size: UInt64?) {
        let current = storageDetails ?? StorageDetails(diskTotal: 0, diskFree: 0, derivedDataSize: nil, buildCacheSize: nil, doltDataSize: nil)
        let updated = StorageDetails(
            diskTotal: current.diskTotal,
            diskFree: current.diskFree,
            derivedDataSize: current.derivedDataSize,
            buildCacheSize: size,
            doltDataSize: current.doltDataSize
        )
        if storageDetails != updated {
            storageDetails = updated
        }
    }

    private func applyTmux(_ data: TmuxData?) {
        guard let data, var agents = agentsDetails else { return }
        // Merge tmux session names with vitals-reported sessions
        let merged = Array(Set(agents.sessionNames + data.sessionNames)).sorted()
        if agents.sessionNames != merged {
            agents = AgentsDetails(
                activeSessions: agents.activeSessions,
                deadSessions: agents.deadSessions,
                orphanProcessCount: agents.orphanProcessCount,
                stuckPatrolCount: agents.stuckPatrolCount,
                zombieSessionCount: agents.zombieSessionCount,
                sessionNames: merged
            )
            agentsDetails = agents
        }
    }

    // MARK: - Deacon Heartbeat

    struct DeaconHeartbeatData: Sendable {
        let sessionAlive: Bool
        let lastHeartbeat: Date?
        let heartbeatAge: TimeInterval?
        let patrolActive: Bool
    }

    private static func fetchDeaconHeartbeat() async -> DeaconHeartbeatData? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let townRoot = Self.resolveTownRoot() else {
                    continuation.resume(returning: nil)
                    return
                }
                let path = (townRoot as NSString).appendingPathComponent("deacon/heartbeat.json")
                guard let data = FileManager.default.contents(atPath: path),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continuation.resume(returning: nil)
                    return
                }

                let sessionAlive = json["session_alive"] as? Bool ?? false
                let patrolActive = json["patrol_active"] as? Bool ?? false

                var lastHeartbeat: Date?
                var heartbeatAge: TimeInterval?
                if let ts = json["timestamp"] as? String {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let date = formatter.date(from: ts) {
                        lastHeartbeat = date
                        heartbeatAge = -date.timeIntervalSinceNow
                    }
                } else if let ts = json["timestamp"] as? TimeInterval {
                    let date = Date(timeIntervalSince1970: ts)
                    lastHeartbeat = date
                    heartbeatAge = -date.timeIntervalSinceNow
                }

                continuation.resume(returning: DeaconHeartbeatData(
                    sessionAlive: sessionAlive,
                    lastHeartbeat: lastHeartbeat,
                    heartbeatAge: heartbeatAge,
                    patrolActive: patrolActive
                ))
            }
        }
    }

    private func applyDeaconHeartbeat(_ data: DeaconHeartbeatData?) {
        guard let data else { return }
        let deacon = DeaconState(
            sessionAlive: data.sessionAlive,
            lastHeartbeat: data.lastHeartbeat,
            heartbeatAge: data.heartbeatAge,
            patrolActive: data.patrolActive
        )
        let currentChain = watchdogChain
        let newChain = WatchdogChainState(
            daemon: currentChain?.daemon ?? DaemonState(pid: nil, running: false, tickInterval: 180),
            boot: currentChain?.boot ?? BootState(lastFireTime: nil, lastDecision: .unknown, lastReason: nil),
            deacon: deacon
        )
        if watchdogChain != newChain {
            watchdogChain = newChain
        }
    }

    // MARK: - Boot Status

    struct BootStatusData: Sendable {
        let lastFireTime: Date?
        let lastDecision: BootDecision
        let lastReason: String?
    }

    private static func fetchBootStatus() async -> BootStatusData? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let townRoot = Self.resolveTownRoot() else {
                    continuation.resume(returning: nil)
                    return
                }
                let path = (townRoot as NSString).appendingPathComponent("deacon/dogs/boot/.boot-status.json")
                guard let data = FileManager.default.contents(atPath: path),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continuation.resume(returning: nil)
                    return
                }

                let decisionStr = json["decision"] as? String ?? "unknown"
                let decision = BootDecision(rawValue: decisionStr) ?? .unknown
                let reason = json["reason"] as? String

                var fireTime: Date?
                if let ts = json["timestamp"] as? String {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    fireTime = formatter.date(from: ts)
                } else if let ts = json["timestamp"] as? TimeInterval {
                    fireTime = Date(timeIntervalSince1970: ts)
                }

                continuation.resume(returning: BootStatusData(
                    lastFireTime: fireTime,
                    lastDecision: decision,
                    lastReason: reason
                ))
            }
        }
    }

    private func applyBootStatus(_ data: BootStatusData?) {
        guard let data else { return }
        let boot = BootState(
            lastFireTime: data.lastFireTime,
            lastDecision: data.lastDecision,
            lastReason: data.lastReason
        )
        let currentChain = watchdogChain
        let newChain = WatchdogChainState(
            daemon: currentChain?.daemon ?? DaemonState(pid: nil, running: false, tickInterval: 180),
            boot: boot,
            deacon: currentChain?.deacon ?? DeaconState(sessionAlive: false, lastHeartbeat: nil, heartbeatAge: nil, patrolActive: false)
        )
        if watchdogChain != newChain {
            watchdogChain = newChain
        }
    }

    // MARK: - Escalations

    private static func fetchEscalations() async -> [EscalationEntry] {
        let result = await GastownCommandRunner.gt(["escalation", "list", "--json"], timeoutSeconds: 10)
        guard result.succeeded,
              let data = result.stdout.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return jsonArray.compactMap { json -> EscalationEntry? in
            guard let id = json["id"] as? String,
                  let severityStr = json["severity"] as? String,
                  let severity = EscalationSeverity(rawValue: severityStr),
                  let summary = json["summary"] as? String else {
                return nil
            }

            let categoryStr = json["category"] as? String ?? "help"
            let category = EscalationCategory(rawValue: categoryStr) ?? .help
            let raisedBy = json["raised_by"] as? String ?? "unknown"
            let acknowledged = json["acknowledged"] as? Bool ?? false

            var raisedAt = Date()
            if let ts = json["raised_at"] as? String {
                raisedAt = formatter.date(from: ts) ?? Date()
            }

            var acknowledgedAt: Date?
            if let ts = json["acknowledged_at"] as? String {
                acknowledgedAt = formatter.date(from: ts)
            }

            return EscalationEntry(
                id: id,
                severity: severity,
                category: category,
                summary: summary,
                raisedBy: raisedBy,
                raisedAt: raisedAt,
                acknowledged: acknowledged,
                acknowledgedAt: acknowledgedAt
            )
        }
        .sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity > rhs.severity
            }
            return lhs.raisedAt < rhs.raisedAt
        }
    }

    private func applyEscalations(_ entries: [EscalationEntry]) {
        if escalations != entries {
            escalations = entries
        }
    }

    // MARK: - Actions

    func startDolt() async -> ActionResult {
        let result = await GastownCommandRunner.gt(["dolt", "start"], timeoutSeconds: 30)
        if result.succeeded {
            await refreshNow()
            return ActionResult(success: true, message: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return ActionResult(success: false, message: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func restartDolt() async -> ActionResult {
        let result = await GastownCommandRunner.gt(["dolt", "restart"], timeoutSeconds: 30)
        if result.succeeded {
            await refreshNow()
            return ActionResult(success: true, message: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return ActionResult(success: false, message: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func cleanDerivedData() async -> ActionResult {
        let home = NSHomeDirectory()
        let path = "\(home)/Library/Developer/Xcode/DerivedData"
        _ = await Self.runShell("/bin/rm", arguments: ["-rf", path])
        // Recreate the directory so Xcode doesn't complain
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        await refreshNow()
        return ActionResult(success: true, message: "DerivedData cleaned")
    }

    func cleanBuildCache() async -> ActionResult {
        // Find and remove /tmp/cmux-* directories
        let output = await Self.runShell("/bin/sh", arguments: ["-c", "rm -rf /tmp/cmux-*"])
        await refreshNow()
        _ = output
        return ActionResult(success: true, message: "Build cache cleaned")
    }

    func restartRefinery(rig: String) async -> ActionResult {
        let result = await GastownCommandRunner.gt(["refinery", "restart", rig], timeoutSeconds: 30)
        if result.succeeded {
            return ActionResult(success: true, message: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return ActionResult(success: false, message: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func acknowledgeEscalation(id: String) async {
        _ = await GastownCommandRunner.gt(["escalation", "ack", id], timeoutSeconds: 10)
        await refreshNow()
    }

    func resolveEscalation(id: String) async {
        _ = await GastownCommandRunner.gt(["escalation", "resolve", id], timeoutSeconds: 10)
        await refreshNow()
    }

    // MARK: - Town Root Resolution

    private static func resolveTownRoot() -> String? {
        let env = ProcessInfo.processInfo.environment
        if let root = env["GT_TOWN_ROOT"], !root.isEmpty {
            return root
        }
        if let root = env["GT_ROOT"], !root.isEmpty {
            return root
        }
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let candidates = [
            (home as NSString).appendingPathComponent("gt"),
            (home as NSString).appendingPathComponent("code/spectralGasTown"),
        ]
        for candidate in candidates {
            let routesPath = (candidate as NSString).appendingPathComponent(".beads/routes.jsonl")
            if fm.fileExists(atPath: routesPath) {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Traffic Light Computation

    private func recomputeTrafficLights() {
        let newSystem = computeSystemStatus()
        if systemStatus != newSystem {
            systemStatus = newSystem
        }

        let newAgents = computeAgentsStatus()
        if agentsStatus != newAgents {
            agentsStatus = newAgents
        }

        let newStorage = computeStorageStatus()
        if storageStatus != newStorage {
            storageStatus = newStorage
        }
    }

    /// System: worst of dolt, daemon, boot, deacon.
    private func computeSystemStatus() -> TrafficLight {
        guard let d = systemDetails else { return .unknown }
        if d.doltServer == nil || !d.daemonRunning { return .red }
        if let w = watchdogChain {
            if !w.deacon.sessionAlive { return .red }
            if w.boot.lastDecision == .wake || w.boot.lastDecision == .start { return .red }
            if w.boot.lastDecision == .nudge { return .amber }
            if let age = w.deacon.heartbeatAge, age > 300 { return .amber }
        }
        if !d.bootWatchdogHealthy || (d.doltCommitGap ?? 0) > 3600 { return .amber }
        return .green
    }

    /// Agents: worst of sessions, orphans, stuck patrols, zombies.
    private func computeAgentsStatus() -> TrafficLight {
        guard let a = agentsDetails else { return .unknown }
        if a.deadSessions > 0 || a.zombieSessionCount > 0 { return .red }
        if a.orphanProcessCount > 0 || a.stuckPatrolCount > 0 { return .amber }
        return .green
    }

    /// Storage: disk thresholds + DerivedData + build cache.
    private func computeStorageStatus() -> TrafficLight {
        guard let s = storageDetails, s.diskTotal > 0 else { return .unknown }
        let freePercent = Double(s.diskFree) / Double(max(s.diskTotal, 1))
        if freePercent < 0.05 { return .red }
        if freePercent < 0.10 { return .amber }
        if (s.derivedDataSize ?? 0) > 20_000_000_000 { return .amber }
        if (s.buildCacheSize ?? 0) > 50_000_000_000 { return .amber }
        return .green
    }

    // MARK: - Doctor Actions

    func runDoctor() async -> DoctorResult {
        let result = await GastownCommandRunner.gt(["doctor", "--json"], timeoutSeconds: 30)
        guard result.succeeded,
              let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let fallback = DoctorResult(passCount: 0, warnCount: 0, failCount: 0, failures: [], warnings: [], timestamp: Date())
            doctorResult = fallback
            return fallback
        }

        let parsed = Self.parseDoctorResult(json)
        doctorResult = parsed
        recomputeTrafficLights()
        return parsed
    }

    func runDoctorFix() async -> [DoctorFixEntry] {
        let result = await GastownCommandRunner.gt(["doctor", "--fix"], timeoutSeconds: 60)
        let output = result.stdout
        var entries: [DoctorFixEntry] = []

        for line in output.components(separatedBy: "\n") where !line.isEmpty {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let status: DoctorFixStatus
            let id: String
            let message: String

            if trimmed.contains("✓") || trimmed.lowercased().contains("fixed") {
                status = .fixed
            } else if trimmed.lowercased().contains("manual") {
                status = .manual
            } else if trimmed.lowercased().contains("unchanged") || trimmed.lowercased().contains("already") {
                status = .unchanged
            } else {
                status = .error
            }

            // Parse "check_name: result message" format
            let parts = trimmed.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                id = String(parts[0]).trimmingCharacters(in: .whitespaces)
                message = String(parts[1]).trimmingCharacters(in: .whitespaces)
            } else {
                id = "fix-\(entries.count)"
                message = trimmed
            }

            entries.append(DoctorFixEntry(id: id, status: status, message: message))
        }

        doctorFixLog = entries
        // Re-run doctor to get updated results
        _ = await runDoctor()
        return entries
    }

    private static func parseDoctorResult(_ json: [String: Any]) -> DoctorResult {
        let checks = json["checks"] as? [[String: Any]] ?? []
        var passCount = 0
        var warnCount = 0
        var failCount = 0
        var failures: [DiagnosticsDoctorCheck] = []
        var warnings: [DiagnosticsDoctorCheck] = []

        for check in checks {
            let statusStr = check["status"] as? String ?? "pass"
            let status = DoctorCheckStatus(rawValue: statusStr) ?? .pass
            let id = check["name"] as? String ?? check["id"] as? String ?? UUID().uuidString
            let message = check["message"] as? String ?? ""
            let fixHint = check["fix_hint"] as? String ?? check["fix"] as? String

            switch status {
            case .pass:
                passCount += 1
            case .warn:
                warnCount += 1
                warnings.append(DiagnosticsDoctorCheck(id: id, status: status, message: message, fixHint: fixHint))
            case .fail:
                failCount += 1
                failures.append(DiagnosticsDoctorCheck(id: id, status: status, message: message, fixHint: fixHint))
            }
        }

        // Fall back to summary counts if provided
        if let summary = json["summary"] as? [String: Any] {
            passCount = summary["pass"] as? Int ?? passCount
            warnCount = summary["warn"] as? Int ?? warnCount
            failCount = summary["fail"] as? Int ?? failCount
        }

        return DoctorResult(
            passCount: passCount,
            warnCount: warnCount,
            failCount: failCount,
            failures: failures,
            warnings: warnings,
            timestamp: Date()
        )
    }

    // MARK: - Formulas

    private static func fetchFormulas() async -> [FormulaEntry] {
        let result = await GastownCommandRunner.bd(["formula", "list", "--json"], timeoutSeconds: 10)
        guard result.succeeded,
              let data = result.stdout.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return jsonArray.compactMap { json -> FormulaEntry? in
            guard let id = json["name"] as? String ?? json["id"] as? String else { return nil }
            let rig = json["rig"] as? String ?? ""
            let statusStr = json["status"] as? String ?? "idle"
            let status = FormulaRunStatus(rawValue: statusStr) ?? .idle
            let elapsed = json["elapsed"] as? TimeInterval
            return FormulaEntry(id: id, rig: rig, status: status, elapsed: elapsed)
        }
    }

    private func applyFormulas(_ entries: [FormulaEntry]) {
        if formulaStatus != entries {
            formulaStatus = entries
        }
    }

    // MARK: - Plugins

    private static func fetchPlugins() async -> [PluginEntry] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let townRoot = Self.resolveTownRoot() else {
                    continuation.resume(returning: [])
                    return
                }
                let path = (townRoot as NSString).appendingPathComponent("deacon/health-check-state.json")
                guard let data = FileManager.default.contents(atPath: path),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let pluginsJson = json["plugins"] as? [[String: Any]] else {
                    continuation.resume(returning: [])
                    return
                }

                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

                let entries = pluginsJson.compactMap { p -> PluginEntry? in
                    guard let id = p["name"] as? String ?? p["id"] as? String else { return nil }
                    let resultStr = p["result"] as? String ?? "pending"
                    let result = PluginResult(rawValue: resultStr) ?? .pending
                    let detail = p["detail"] as? String ?? p["message"] as? String

                    var lastRun: Date?
                    if let ts = p["last_run"] as? String { lastRun = formatter.date(from: ts) }
                    else if let ts = p["last_run"] as? TimeInterval { lastRun = Date(timeIntervalSince1970: ts) }

                    var nextRun: Date?
                    if let ts = p["next_run"] as? String { nextRun = formatter.date(from: ts) }
                    else if let ts = p["next_run"] as? TimeInterval { nextRun = Date(timeIntervalSince1970: ts) }

                    return PluginEntry(id: id, lastRun: lastRun, result: result, nextRun: nextRun, detail: detail)
                }

                continuation.resume(returning: entries)
            }
        }
    }

    private func applyPlugins(_ entries: [PluginEntry]) {
        if plugins != entries {
            plugins = entries
        }
    }

    // MARK: - Event Stream

    /// Start streaming events from `gt log --follow`.
    func startEventStream() {
        guard eventStreamTask == nil else { return }
        eventStreamTask = Task { [weak self] in
            var retries = 0
            let maxRetries = 3

            while !Task.isCancelled, retries <= maxRetries {
                do {
                    try await self?.streamEvents()
                } catch is CancellationError {
                    break
                } catch {
                    retries += 1
                    if retries > maxRetries { break }
                    try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s retry
                }
            }
        }
    }

    /// Stop the event stream.
    func stopEventStream() {
        eventStreamTask?.cancel()
        eventStreamTask = nil
    }

    private func streamEvents() async throws {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")

        // Resolve gt path
        let gtPath = ProcessInfo.processInfo.environment["GT_BIN"]
            ?? "/usr/local/bin/gt"

        process.executableURL = URL(fileURLWithPath: gtPath)
        process.arguments = ["log", "--follow"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()

        let handle = pipe.fileHandleForReading
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for try await line in handle.bytes.lines {
            if Task.isCancelled {
                process.terminate()
                break
            }

            let entry = Self.parseEventLine(line, formatter: formatter)
            await MainActor.run { [weak self] in
                guard let self else { return }
                var events = self.recentEvents
                events.insert(entry, at: 0)
                if events.count > Self.eventBufferSize {
                    events = Array(events.prefix(Self.eventBufferSize))
                }
                self.recentEvents = events
            }
        }

        process.terminate()
        process.waitUntilExit()
    }

    nonisolated private static func parseEventLine(_ line: String, formatter: ISO8601DateFormatter) -> EventEntry {
        // Expected format: "2026-04-11T14:23:01Z [mayor] Slung bead hq-2i0 to diagnostics_designer"
        // Or simpler: "14:23:01  [mayor]  message text"
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        var timestamp = Date()
        var actor: String?
        var message = trimmed
        var kind: String?

        // Try to parse ISO timestamp at start
        if trimmed.count > 20, let spaceIdx = trimmed.firstIndex(of: " ") {
            let tsCandidate = String(trimmed[trimmed.startIndex..<spaceIdx])
            if let parsed = formatter.date(from: tsCandidate) {
                timestamp = parsed
                message = String(trimmed[trimmed.index(after: spaceIdx)...]).trimmingCharacters(in: .whitespaces)
            }
        }

        // Try to extract [actor] from message
        if message.hasPrefix("["), let closing = message.firstIndex(of: "]") {
            actor = String(message[message.index(after: message.startIndex)..<closing])
            message = String(message[message.index(after: closing)...]).trimmingCharacters(in: .whitespaces)
        }

        // Infer event kind from keywords
        if message.lowercased().contains("merge") { kind = "merge" }
        else if message.lowercased().contains("slung") || message.lowercased().contains("dispatch") { kind = "dispatch" }
        else if message.lowercased().contains("decision") || message.lowercased().contains("boot") { kind = "watchdog" }
        else if message.lowercased().contains("health") || message.lowercased().contains("check") { kind = "health" }
        else if message.lowercased().contains("error") || message.lowercased().contains("fail") { kind = "error" }

        return EventEntry(
            id: UUID().uuidString,
            timestamp: timestamp,
            actor: actor,
            message: message,
            kind: kind
        )
    }

    // MARK: - Shell Helpers

    private static func runShell(_ executable: String, arguments: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                guard process.terminationStatus == 0 else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: String(data: data, encoding: .utf8))
            }
        }
    }

    private static func fetchDirectorySize(_ path: String) async -> UInt64? {
        let output = await runShell("/usr/bin/du", arguments: ["-sk", path])
        guard let output else { return nil }
        let parts = output.split(separator: "\t", maxSplits: 1)
        guard let kb = UInt64(parts.first ?? "") else { return nil }
        return kb * 1024
    }
}

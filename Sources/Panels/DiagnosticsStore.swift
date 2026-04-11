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

    // MARK: - Meta

    @Published private(set) var isRefreshing: Bool = false
    @Published private(set) var lastRefresh: Date?

    // MARK: - Polling

    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?

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
    }

    /// Stop automatic polling.
    func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        refreshTask?.cancel()
        refreshTask = nil
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

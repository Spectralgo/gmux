import Foundation

// MARK: - Diagnostics Panel Models
//
// Model types for the Engine Room (Diagnostics Panel).
// Phase 1: traffic lights, system/agents/storage details.

/// Traffic light status for a diagnostics domain.
enum TrafficLight: Equatable, Sendable {
    /// Initial state, no data yet.
    case unknown
    /// All checks passing.
    case green
    /// Non-critical issues.
    case amber
    /// Critical failure.
    case red

    var displayLabel: String {
        switch self {
        case .unknown:
            return String(localized: "trafficLight.unknown", defaultValue: "Checking…")
        case .green:
            return String(localized: "trafficLight.green", defaultValue: "Healthy")
        case .amber:
            return String(localized: "trafficLight.amber", defaultValue: "Attention")
        case .red:
            return String(localized: "trafficLight.red", defaultValue: "Critical")
        }
    }
}

// MARK: - System Details

struct DoltServerInfo: Equatable, Sendable {
    let port: Int
    let pid: Int
    let memoryMB: Double
    let connections: Int
    let maxConnections: Int
}

struct SystemDetails: Equatable, Sendable {
    let doltServer: DoltServerInfo?
    let daemonPID: Int?
    let daemonRunning: Bool
    let bootWatchdogHealthy: Bool
    let deaconHeartbeatFresh: Bool
    let doltCommitGap: TimeInterval?
}

// MARK: - Agents Details

struct AgentsDetails: Equatable, Sendable {
    let activeSessions: Int
    let deadSessions: Int
    let orphanProcessCount: Int
    let stuckPatrolCount: Int
    let zombieSessionCount: Int
    let sessionNames: [String]
}

// MARK: - Storage Details

struct StorageDetails: Equatable, Sendable {
    let diskTotal: UInt64
    let diskFree: UInt64
    let derivedDataSize: UInt64?
    let buildCacheSize: UInt64?
    let doltDataSize: UInt64?
}

// MARK: - Watchdog Chain

struct WatchdogChainState: Equatable, Sendable {
    let daemon: DaemonState
    let boot: BootState
    let deacon: DeaconState
}

struct DaemonState: Equatable, Sendable {
    let pid: Int?
    let running: Bool
    let tickInterval: TimeInterval
}

struct BootState: Equatable, Sendable {
    let lastFireTime: Date?
    let lastDecision: BootDecision
    let lastReason: String?
}

enum BootDecision: String, Equatable, Sendable {
    case nothing
    case nudge
    case wake
    case start
    case unknown
}

struct DeaconState: Equatable, Sendable {
    let sessionAlive: Bool
    let lastHeartbeat: Date?
    let heartbeatAge: TimeInterval?
    let patrolActive: Bool
}

// MARK: - Escalation Queue

struct EscalationEntry: Equatable, Identifiable, Sendable {
    let id: String
    let severity: EscalationSeverity
    let category: EscalationCategory
    let summary: String
    let raisedBy: String
    let raisedAt: Date
    let acknowledged: Bool
    let acknowledgedAt: Date?
}

enum EscalationSeverity: String, Equatable, Comparable, Sendable {
    case medium
    case high
    case critical

    static func < (lhs: Self, rhs: Self) -> Bool {
        let order: [Self] = [.medium, .high, .critical]
        return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }
}

enum EscalationCategory: String, Equatable, Sendable {
    case decision
    case help
    case blocked
    case failed
    case emergency
    case gateTimeout = "gate_timeout"
    case lifecycle
}

// MARK: - Action Result

struct ActionResult: Equatable, Sendable {
    let success: Bool
    let message: String
}

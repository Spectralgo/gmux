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

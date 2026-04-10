import Foundation

// MARK: - Rig Health Indicators
//
// Models for the Rig Panel's Health section — traffic-light status for
// build, CI, Dolt, disk, and doctor checks. Consumed by RigPanelAdapter
// and rendered in RigHealthSection.

/// Traffic-light signal for a single health dimension.
enum HealthSignal: Equatable, Sendable {
    /// System is healthy.
    case green(String)
    /// System needs attention but is not broken.
    case amber(String)
    /// System requires immediate action.
    case red(String)
    /// Status could not be determined.
    case unknown(String)

    /// Human-readable message for display.
    var message: String {
        switch self {
        case .green(let msg), .amber(let msg), .red(let msg), .unknown(let msg):
            return msg
        }
    }
}

/// Aggregated results from `gt doctor`.
struct DoctorSummary: Equatable, Sendable {
    let passCount: Int
    let warnCount: Int
    let failCount: Int
    let details: [DoctorCheckResult]
}

/// A single check result from `gt doctor --json`.
struct DoctorCheckResult: Equatable, Sendable, Identifiable {
    var id: String { name }
    let name: String
    let status: DoctorCheckStatus
    let message: String
}

/// Status of a single doctor check.
enum DoctorCheckStatus: String, Equatable, Sendable {
    case pass
    case warn
    case fail
}

/// Health indicators for a rig, displayed in the Health section.
struct RigHealthIndicators: Equatable, Sendable {
    let build: HealthSignal
    let ci: HealthSignal
    let dolt: HealthSignal
    let disk: HealthSignal
    let doctor: DoctorSummary

    /// Overall signal derived from the worst individual signal.
    var doctorSignal: HealthSignal {
        if doctor.failCount > 0 {
            return .red("\(doctor.passCount) pass / \(doctor.warnCount) warn / \(doctor.failCount) fail")
        } else if doctor.warnCount > 0 {
            return .amber("\(doctor.passCount) pass / \(doctor.warnCount) warn / \(doctor.failCount) fail")
        } else {
            return .green("\(doctor.passCount) pass")
        }
    }
}

import Foundation

/// Structured health indicators for a rig.
///
/// Health issues are collected during rig discovery and represent problems
/// that may affect downstream navigation or automation. A rig with only
/// warnings is still usable; a rig with errors may not function correctly.
struct RigHealth: Equatable {
    /// All health issues discovered for this rig.
    let issues: [HealthIssue]

    /// Whether the rig has no health issues at all.
    var isHealthy: Bool { issues.isEmpty }

    /// Whether any issue has error severity.
    var hasErrors: Bool { issues.contains { $0.severity == .error } }

    /// Whether any issue has warning severity (but no errors).
    var hasWarnings: Bool { issues.contains { $0.severity == .warning } }
}

/// A single health issue discovered during rig inventory.
struct HealthIssue: Equatable {
    let severity: Severity
    let category: Category
    let message: String

    enum Severity: Equatable {
        case warning
        case error
    }

    enum Category: String, Equatable {
        /// The rig's `config.json` is missing.
        case missingConfig

        /// A role directory is missing from the rig.
        case missingRoleDirectory

        /// The rig's `config.json` exists but cannot be decoded.
        case invalidConfig

        /// The rig's `.beads/` directory is missing.
        case missingBeads
    }
}

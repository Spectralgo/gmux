import Foundation

/// Decoded representation of `<rig>/config.json`.
///
/// Each rig directory contains a `config.json` that identifies the rig,
/// its source repository, default branch, and beads prefix.
struct RigConfig: Codable, Equatable {
    let type: String
    let version: Int
    let name: String
    let git_url: String
    let default_branch: String
    let beads: RigConfigBeads

    /// Operational status: "operational", "parked", or "docked".
    let status: String?
    /// Maximum number of polecats allowed in this rig.
    let max_polecats: Int?
    /// Whether polecats auto-restart on failure.
    let auto_restart: Bool?
    /// Do not disturb — suppresses notifications and nudges.
    let dnd: Bool?
    /// Name pool used when spawning polecats.
    let namepool: String?
}

/// Beads configuration from the per-rig config.
struct RigConfigBeads: Codable, Equatable {
    let prefix: String
}

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

    // CodingKeys not needed — property names match JSON snake_case keys.
}

/// Beads configuration from the per-rig config.
struct RigConfigBeads: Codable, Equatable {
    let prefix: String
}

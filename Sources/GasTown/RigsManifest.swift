import Foundation

/// Decoded representation of `<town>/rigs.json`.
///
/// This is the Town-level registry of all rigs. Each key in `rigs` is the
/// rig name and maps to its manifest entry.
struct RigsManifest: Codable, Equatable {
    let version: Int
    let rigs: [String: RigManifestEntry]
}

/// A single rig entry within the Town's `rigs.json`.
struct RigManifestEntry: Codable, Equatable {
    let git_url: String
    let added_at: String
    let beads: RigManifestBeads

    // CodingKeys not needed — property names match JSON snake_case keys.
}

/// Beads configuration from the Town-level manifest.
struct RigManifestBeads: Codable, Equatable {
    let repo: String
    let prefix: String
}

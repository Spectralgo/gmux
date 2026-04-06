import Foundation

/// An immutable point-in-time snapshot of all discovered rigs in a Town.
///
/// Carries both successfully discovered rigs and per-rig failures so that
/// one broken rig does not prevent the rest from being usable.
struct RigInventorySnapshot: Equatable {
    /// The Town root this inventory was discovered from.
    let town: GasTownRoot

    /// Successfully discovered rigs.
    let rigs: [Rig]

    /// Rigs that failed discovery, with diagnostic information.
    let failures: [RigDiscoveryFailure]

    /// When this snapshot was created.
    let timestamp: Date

    /// Rigs with no health issues.
    var healthyRigs: [Rig] { rigs.filter(\.health.isHealthy) }

    /// Whether any rigs failed discovery entirely.
    var hasFailures: Bool { !failures.isEmpty }
}

/// A rig that could not be discovered, with a diagnostic reason.
struct RigDiscoveryFailure: Equatable, Error {
    /// The rig name from `rigs.json`.
    let rigName: String

    /// The expected path to the rig root.
    let rigPath: URL

    /// Human-readable description of why discovery failed.
    let reason: String
}

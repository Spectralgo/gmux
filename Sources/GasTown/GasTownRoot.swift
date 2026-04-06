import Foundation

/// A validated Gas Town root directory.
///
/// Represents a filesystem location that has been confirmed as a Gas Town
/// installation. TASK-007 (Town root detection) is responsible for producing
/// this value; downstream consumers should never construct it from an
/// unvalidated path.
struct GasTownRoot: Equatable, Hashable {
    /// Absolute path to the Town root directory (e.g. `~/code/spectralGasTown`).
    let path: URL
}

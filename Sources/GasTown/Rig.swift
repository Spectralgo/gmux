import Foundation

/// A discovered rig within a Gas Town.
///
/// The `id` is the rig name from `rigs.json` (e.g. `"gmux"`, `"spectralChat"`).
/// It is stable across refreshes and suitable for use as a navigation key.
struct Rig: Identifiable, Equatable {
    /// Stable identifier — the rig name from `rigs.json`.
    let id: String

    /// Display name (currently always equal to `id`).
    let name: String

    /// Absolute path to the rig root directory.
    let path: URL

    /// Parsed `config.json` from the rig root.
    let config: RigConfig

    /// Discovered role directories keyed by role.
    let roles: [RigRole: RoleDirectory]

    /// Structured health indicators for this rig.
    let health: RigHealth
}

/// The standard role directories within a rig.
///
/// Singular roles (`mayor`, `refinery`, `witness`) contain a single workspace
/// at `<role>/rig/`. Multi-member roles (`crew`, `polecats`) contain named
/// subdirectories, each holding a workspace.
enum RigRole: String, CaseIterable, Codable, Equatable, Hashable {
    case mayor
    case crew
    case polecats
    case refinery
    case witness

    /// Whether this role has a single unnamed workspace (`<role>/rig/`)
    /// rather than named member subdirectories.
    var isSingular: Bool {
        switch self {
        case .mayor, .refinery, .witness: return true
        case .crew, .polecats: return false
        }
    }
}

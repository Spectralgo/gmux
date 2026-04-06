import Foundation

/// Discovery result for a single role directory within a rig.
///
/// For singular roles (mayor, refinery, witness) `members` is empty and
/// the workspace lives at `<role>/rig/`. For multi-member roles (crew,
/// polecats) `members` lists subdirectory names found under the role path.
///
/// This type intentionally does NOT resolve members to worktree paths or
/// classify workspace types — that is TASK-009 (worktree classifier).
struct RoleDirectory: Equatable {
    /// Which role this directory represents.
    let role: RigRole

    /// Absolute path to the role directory (e.g. `<rig>/crew/`).
    let path: URL

    /// Discovery status of this role directory.
    let status: RoleStatus

    /// Named members found in this role directory.
    ///
    /// Populated for multi-member roles (`crew`, `polecats`) by listing
    /// subdirectories. Empty for singular roles and for missing/empty
    /// directories.
    let members: [String]
}

/// Discovery status of a role directory.
enum RoleStatus: Equatable {
    /// Directory exists and contains expected structure.
    case present

    /// Directory exists but contains no members or workspace.
    case empty

    /// Directory does not exist at the expected path.
    case missing

    /// Directory exists but its structure is unexpected.
    case malformed(String)
}

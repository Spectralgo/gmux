import Foundation

// MARK: - Hooks Adapter
//
// Read-only adapter over the Gas Town hooks CLI (`gt hooks`).
// Normalizes hook targets, sync status, and scope information into
// app models that downstream views and future write flows can consume
// without embedding shell invocations or JSON parsing in UI code.
//
// Consumed by: TASK-019 (hooks edit), TASK-020 (hooks sync), and
// hooks status UI surfaces.
//
// Design: stateless, value-oriented, injectable environment (same
// pattern as BeadsAdapter). All models are Equatable + Sendable.

// MARK: - Domain Models

/// The sync status of a single hook target.
///
/// Distinguishes between targets that are in sync with the generated
/// configuration, targets that need a sync, and targets whose settings
/// file is missing entirely.
enum HookSyncStatus: String, Equatable, Sendable {
    /// The settings file matches the generated configuration.
    case inSync = "in sync"

    /// The settings file exists but differs from the generated configuration.
    case outOfSync = "out of sync"

    /// The settings file does not exist at the expected path.
    case missing = "missing"

    /// The status string was not recognized.
    case unknown = "unknown"
}

/// Parsed scope information from a hook target path.
///
/// Target paths follow the pattern `"<rig>/<role>"` for rig-scoped
/// targets, or just `"<role>"` for town-level targets (e.g. `"mayor"`).
/// This type extracts rig and role from the target string so callers
/// don't need to parse slash-separated paths.
struct HookScope: Equatable, Sendable {
    /// Rig name, or `nil` for town-level targets.
    let rig: String?

    /// Role within the rig (e.g. `"crew"`, `"polecats"`, `"witness"`)
    /// or the standalone role name for town-level targets (e.g. `"mayor"`).
    let role: String

    /// The raw target string as returned by `gt hooks list --json`.
    let raw: String
}

/// A single managed hook target as returned by `gt hooks list --json`.
///
/// Each target represents a `.claude/settings.json` location that
/// Gas Town manages via base configuration and optional overrides.
struct HookTarget: Equatable, Sendable, Identifiable {
    /// Stable identifier — the target path (e.g. `"gmux/polecats"`).
    var id: String { scope.raw }

    /// Parsed scope (rig + role) derived from the target path.
    let scope: HookScope

    /// Override file names applied to this target, if any.
    let overrides: [String]

    /// Whether the settings file is in sync with generated configuration.
    let syncStatus: HookSyncStatus

    /// Absolute path to the managed `.claude/settings.json` file.
    let settingsPath: String

    /// Whether the settings file exists on disk.
    let settingsFileExists: Bool
}

/// Point-in-time snapshot of all hook targets and infrastructure paths.
///
/// This snapshot is the primary output of the hooks adapter. It carries
/// both the list of discovered targets and the infrastructure paths
/// (base config, overrides directory) so downstream consumers can
/// reason about the hooks system as a whole.
struct HooksSnapshot: Equatable, Sendable {
    /// All discovered hook targets.
    let targets: [HookTarget]

    /// Absolute path to the base hooks configuration file.
    let basePath: String

    /// Absolute path to the overrides directory.
    let overridesDir: String

    /// When this snapshot was captured.
    let timestamp: Date

    /// Targets that are out of sync or missing.
    var needsSync: [HookTarget] {
        targets.filter { $0.syncStatus != .inSync }
    }

    /// Whether all targets are in sync.
    var allInSync: Bool {
        targets.allSatisfy { $0.syncStatus == .inSync }
    }

    /// Targets grouped by rig name. Town-level targets use `nil` key.
    var targetsByRig: [String?: [HookTarget]] {
        Dictionary(grouping: targets, by: { $0.scope.rig })
    }

    /// Number of targets in each sync status.
    var statusSummary: [HookSyncStatus: Int] {
        Dictionary(grouping: targets, by: { $0.syncStatus })
            .mapValues(\.count)
    }
}

// MARK: - Error Types

/// Structured error describing why a hooks adapter operation failed.
///
/// Each case carries enough context for the caller to display an
/// actionable message. The distinction between `gtCLINotFound` and
/// `cliFailure` lets views tell the user whether the problem is
/// infrastructure (missing tooling) or data (bad output).
enum HooksAdapterError: Error, Equatable, Sendable {
    /// The `gt` CLI binary could not be found on PATH.
    case gtCLINotFound

    /// The `gt` CLI exited with a non-zero status.
    case cliFailure(command: String, exitCode: Int32, stderr: String)

    /// The CLI produced output that could not be parsed as JSON.
    case parseFailure(command: String, detail: String)
}

// MARK: - Load State

/// Wraps a hooks adapter result so views can distinguish between
/// "no data yet", "data loaded", and "failed with reason".
enum HooksLoadState<T: Equatable & Sendable>: Equatable, Sendable {
    case idle
    case loading
    case loaded(T)
    case failed(HooksAdapterError)
}

// MARK: - Adapter

/// Read-only adapter for Gas Town hooks data.
///
/// Designed as a stateless value-oriented service. Downstream views hold
/// their own `HooksLoadState` and call adapter methods to populate it.
///
/// Follows the same testability pattern as `BeadsAdapter`: an injectable
/// `Environment` allows tests to stub CLI resolution and process execution.
struct HooksAdapter {

    // MARK: - Configuration

    /// Abstraction over CLI access for testability.
    struct Environment: Sendable {
        var whichGT: @Sendable () -> String?
        var runCLI: @Sendable (_ executablePath: String, _ arguments: [String]) -> GasTownCLIRunner.CLIResult

        static let live = Environment(
            whichGT: {
                GasTownCLIRunner.resolveGTCLI()
            },
            runCLI: { executablePath, arguments in
                GasTownCLIRunner.runProcess(executablePath: executablePath, arguments: arguments)
            }
        )
    }

    let environment: Environment

    init(environment: Environment = .live) {
        self.environment = environment
    }

    /// Convenience initializer that wires a known town root path into
    /// the CLI environment so child processes get GT_TOWN_ROOT and BEADS_DIR
    /// even when running inside a GUI app (where env vars are not inherited).
    init(townRootPath: String) {
        self.environment = Environment(
            whichGT: { GasTownCLIRunner.resolveGTCLI() },
            runCLI: { executablePath, arguments in
                GasTownCLIRunner.runProcess(
                    executablePath: executablePath,
                    arguments: arguments,
                    townRootPath: townRootPath
                )
            }
        )
    }

    // MARK: - Public API

    /// Load all managed hook targets and their sync status.
    ///
    /// Invokes `gt hooks list --json` and normalizes the result into a
    /// `HooksSnapshot`. This is the primary entry point for hooks
    /// ingestion — it provides everything needed for status display and
    /// later write flows.
    func loadHooks() -> Result<HooksSnapshot, HooksAdapterError> {
        guard let gtPath = environment.whichGT() else {
            return .failure(.gtCLINotFound)
        }

        let result = environment.runCLI(gtPath, ["hooks", "list", "--json"])

        if result.exitCode != 0 {
            let stderr = String(data: result.stderr, encoding: .utf8) ?? ""
            return .failure(.cliFailure(
                command: "gt hooks list --json",
                exitCode: result.exitCode,
                stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }

        guard let json = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any] else {
            let raw = String(data: result.stdout, encoding: .utf8) ?? "<binary>"
            return .failure(.parseFailure(
                command: "gt hooks list --json",
                detail: String(
                    localized: "hooks.list.parseFailed",
                    defaultValue: "Expected JSON object from 'gt hooks list --json'. Got: \(raw.prefix(200))"
                )
            ))
        }

        return parseHooksListJSON(json)
    }

    // MARK: - JSON Parsing

    /// Parse the top-level `gt hooks list --json` response.
    private func parseHooksListJSON(
        _ json: [String: Any]
    ) -> Result<HooksSnapshot, HooksAdapterError> {
        guard let targetsArray = json["targets"] as? [[String: Any]] else {
            return .failure(.parseFailure(
                command: "gt hooks list --json",
                detail: String(
                    localized: "hooks.list.noTargets",
                    defaultValue: "Response missing 'targets' array."
                )
            ))
        }

        let basePath = json["base_path"] as? String ?? ""
        let overridesDir = json["overrides_dir"] as? String ?? ""

        let targets = targetsArray.compactMap { parseHookTarget($0) }

        return .success(HooksSnapshot(
            targets: targets,
            basePath: basePath,
            overridesDir: overridesDir,
            timestamp: Date()
        ))
    }

    /// Parse a single target entry from the `targets` array.
    private func parseHookTarget(_ json: [String: Any]) -> HookTarget? {
        guard let target = json["target"] as? String,
              let path = json["path"] as? String else {
            return nil
        }

        let scope = parseScope(target)

        let statusString = json["status"] as? String ?? "unknown"
        let syncStatus = HookSyncStatus(rawValue: statusString) ?? .unknown

        let overrides: [String]
        if let overrideArray = json["overrides"] as? [String] {
            overrides = overrideArray
        } else {
            overrides = []
        }

        let exists = json["exists"] as? Bool ?? false

        return HookTarget(
            scope: scope,
            overrides: overrides,
            syncStatus: syncStatus,
            settingsPath: path,
            settingsFileExists: exists
        )
    }

    /// Parse a target string into rig/role components.
    ///
    /// Target paths are either `"<role>"` for town-level targets or
    /// `"<rig>/<role>"` for rig-scoped targets. Deeper paths like
    /// `"<rig>/<role>/<sub>"` are preserved with the last component
    /// as the role and everything before the last slash as the rig.
    private func parseScope(_ target: String) -> HookScope {
        let components = target.split(separator: "/", maxSplits: 1)
        if components.count == 1 {
            return HookScope(rig: nil, role: String(components[0]), raw: target)
        }
        return HookScope(
            rig: String(components[0]),
            role: String(components[1]),
            raw: target
        )
    }

}

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
        var runCLI: @Sendable (_ executablePath: String, _ arguments: [String]) -> CLIResult

        static let live = Environment(
            whichGT: {
                HooksAdapter.resolveGTCLI()
            },
            runCLI: { executablePath, arguments in
                HooksAdapter.runProcess(executablePath: executablePath, arguments: arguments)
            }
        )
    }

    /// Result of running a CLI command.
    struct CLIResult: Equatable, Sendable {
        let exitCode: Int32
        let stdout: Data
        let stderr: Data
    }

    let environment: Environment

    init(environment: Environment = .live) {
        self.environment = environment
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

    // MARK: - CLI Helpers

    /// Attempt to find the `gt` binary on PATH.
    static func resolveGTCLI() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["gt"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let path, !path.isEmpty {
                    return path
                }
            }
        } catch {
            // which not available or failed — gt not on PATH.
        }
        return nil
    }

    /// Run a CLI process and capture stdout + stderr.
    static func runProcess(executablePath: String, arguments: [String]) -> CLIResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return CLIResult(
                exitCode: -1,
                stdout: Data(),
                stderr: Data("Failed to launch process: \(error.localizedDescription)".utf8)
            )
        }

        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return CLIResult(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )
    }
}

// MARK: - Write Domain Models
//
// Models for hooks diff, edit, and sync write actions (TASK-019).
// These build on the read-only models above and surface clear
// success, failure, and out-of-sync states.

/// Identifies which configuration surface to edit.
enum HookEditTarget: Equatable, Sendable {
    /// The base hooks configuration file.
    case base
    /// An override file for a specific target scope.
    case override(target: String)
}

/// The result of resolving an edit target to a filesystem path.
struct HookEditResolution: Equatable, Sendable {
    /// What was requested for editing.
    let editTarget: HookEditTarget
    /// Absolute path to the editable file.
    let filePath: String
    /// Whether the file currently exists on disk.
    let fileExists: Bool
}

/// A single target's diff between current settings and generated configuration.
struct HookDiffEntry: Equatable, Sendable, Identifiable {
    var id: String { target }

    /// The target path (e.g. `"gmux/polecats"`).
    let target: String

    /// Sync status of this target.
    let status: HookSyncStatus

    /// Human-readable diff output, or `nil` if the target is in sync.
    let diff: String?
}

/// Point-in-time diff report across all hook targets.
struct HooksDiffReport: Equatable, Sendable {
    /// Per-target diff entries.
    let entries: [HookDiffEntry]

    /// When this report was generated.
    let timestamp: Date

    /// Whether any target has pending changes.
    var hasChanges: Bool {
        entries.contains { $0.status != .inSync }
    }

    /// Only entries that are out of sync or missing.
    var changedEntries: [HookDiffEntry] {
        entries.filter { $0.status != .inSync }
    }
}

/// Per-target outcome after a sync operation.
enum HookSyncResultStatus: String, Equatable, Sendable {
    /// The target's settings file was regenerated.
    case updated
    /// The target was already in sync — no changes made.
    case alreadyInSync = "already_in_sync"
    /// The sync failed for this target.
    case failed
}

/// A single target's sync result.
struct HookSyncTargetResult: Equatable, Sendable, Identifiable {
    var id: String { target }

    /// The target path.
    let target: String

    /// What happened during sync.
    let resultStatus: HookSyncResultStatus

    /// Optional detail message (e.g. error reason for failures).
    let detail: String?
}

/// Full sync report with per-target details.
struct HooksSyncReport: Equatable, Sendable {
    /// Per-target results.
    let results: [HookSyncTargetResult]

    /// When the sync was performed.
    let timestamp: Date

    /// Whether all targets were successfully synced or already in sync.
    var allSucceeded: Bool {
        results.allSatisfy { $0.resultStatus != .failed }
    }

    /// Number of targets that were updated.
    var updatedCount: Int {
        results.filter { $0.resultStatus == .updated }.count
    }

    /// Number of targets that failed to sync.
    var failedCount: Int {
        results.filter { $0.resultStatus == .failed }.count
    }
}

// MARK: - Write API

extension HooksAdapter {

    /// Compute the diff between current hook settings and generated configuration.
    ///
    /// Invokes `gt hooks diff --json` and normalizes the result into a
    /// `HooksDiffReport`. Each entry carries the target, its sync status,
    /// and the textual diff (if any).
    func diffHooks() -> Result<HooksDiffReport, HooksAdapterError> {
        guard let gtPath = environment.whichGT() else {
            return .failure(.gtCLINotFound)
        }

        let result = environment.runCLI(gtPath, ["hooks", "diff", "--json"])

        if result.exitCode != 0 {
            let stderr = String(data: result.stderr, encoding: .utf8) ?? ""
            return .failure(.cliFailure(
                command: "gt hooks diff --json",
                exitCode: result.exitCode,
                stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }

        guard let json = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any] else {
            let raw = String(data: result.stdout, encoding: .utf8) ?? "<binary>"
            return .failure(.parseFailure(
                command: "gt hooks diff --json",
                detail: String(
                    localized: "hooks.diff.parseFailed",
                    defaultValue: "Expected JSON object from 'gt hooks diff --json'. Got: \(raw.prefix(200))"
                )
            ))
        }

        return parseDiffJSON(json)
    }

    /// Resolve the filesystem path for editing a hook configuration surface.
    ///
    /// Uses the snapshot's infrastructure paths to derive the correct edit
    /// target. This avoids invoking the CLI just to find a file path — the
    /// snapshot already carries `basePath` and `overridesDir`.
    ///
    /// - Parameters:
    ///   - editTarget: Whether to edit the base configuration or a specific override.
    ///   - snapshot: A recent `HooksSnapshot` providing infrastructure paths.
    /// - Returns: A `HookEditResolution` with the file path and existence status.
    func resolveEditPath(
        _ editTarget: HookEditTarget,
        snapshot: HooksSnapshot
    ) -> Result<HookEditResolution, HooksAdapterError> {
        switch editTarget {
        case .base:
            let path = snapshot.basePath
            guard !path.isEmpty else {
                return .failure(.parseFailure(
                    command: "resolveEditPath",
                    detail: String(
                        localized: "hooks.edit.noBasePath",
                        defaultValue: "Snapshot does not contain a base configuration path."
                    )
                ))
            }
            let exists = FileManager.default.fileExists(atPath: path)
            return .success(HookEditResolution(
                editTarget: editTarget,
                filePath: path,
                fileExists: exists
            ))

        case .override(let target):
            let overridesDir = snapshot.overridesDir
            guard !overridesDir.isEmpty else {
                return .failure(.parseFailure(
                    command: "resolveEditPath",
                    detail: String(
                        localized: "hooks.edit.noOverridesDir",
                        defaultValue: "Snapshot does not contain an overrides directory path."
                    )
                ))
            }
            // Override files are named after the target with slashes replaced
            // by dashes (e.g. "gmux/polecats" → "gmux-polecats.json").
            let sanitized = target.replacingOccurrences(of: "/", with: "-")
            let path = (overridesDir as NSString).appendingPathComponent("\(sanitized).json")
            let exists = FileManager.default.fileExists(atPath: path)
            return .success(HookEditResolution(
                editTarget: editTarget,
                filePath: path,
                fileExists: exists
            ))
        }
    }

    /// Sync hook settings by applying the Gastown merge strategy.
    ///
    /// Invokes `gt hooks sync` (optionally scoped to specific targets) and
    /// parses the result into a `HooksSyncReport`. The merge strategy
    /// follows the Gastown inheritance model: base → role → rig+role.
    ///
    /// - Parameter targets: Optional list of target paths to sync. When `nil`,
    ///   all targets are synced.
    /// - Returns: A `HooksSyncReport` with per-target results.
    func syncHooks(targets: [String]? = nil) -> Result<HooksSyncReport, HooksAdapterError> {
        guard let gtPath = environment.whichGT() else {
            return .failure(.gtCLINotFound)
        }

        var arguments = ["hooks", "sync", "--json"]
        if let targets {
            for target in targets {
                arguments.append(contentsOf: ["--target", target])
            }
        }

        let result = environment.runCLI(gtPath, arguments)

        if result.exitCode != 0 {
            let stderr = String(data: result.stderr, encoding: .utf8) ?? ""
            return .failure(.cliFailure(
                command: "gt hooks sync --json",
                exitCode: result.exitCode,
                stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }

        guard let json = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any] else {
            let raw = String(data: result.stdout, encoding: .utf8) ?? "<binary>"
            return .failure(.parseFailure(
                command: "gt hooks sync --json",
                detail: String(
                    localized: "hooks.sync.parseFailed",
                    defaultValue: "Expected JSON object from 'gt hooks sync --json'. Got: \(raw.prefix(200))"
                )
            ))
        }

        return parseSyncJSON(json)
    }

    // MARK: - Write JSON Parsing

    /// Parse the `gt hooks diff --json` response.
    private func parseDiffJSON(
        _ json: [String: Any]
    ) -> Result<HooksDiffReport, HooksAdapterError> {
        guard let targetsArray = json["targets"] as? [[String: Any]] else {
            return .failure(.parseFailure(
                command: "gt hooks diff --json",
                detail: String(
                    localized: "hooks.diff.noTargets",
                    defaultValue: "Response missing 'targets' array."
                )
            ))
        }

        let entries = targetsArray.compactMap { entry -> HookDiffEntry? in
            guard let target = entry["target"] as? String else { return nil }
            let statusString = entry["status"] as? String ?? "unknown"
            let status = HookSyncStatus(rawValue: statusString) ?? .unknown
            let diff = entry["diff"] as? String
            return HookDiffEntry(target: target, status: status, diff: diff)
        }

        return .success(HooksDiffReport(entries: entries, timestamp: Date()))
    }

    /// Parse the `gt hooks sync --json` response.
    private func parseSyncJSON(
        _ json: [String: Any]
    ) -> Result<HooksSyncReport, HooksAdapterError> {
        guard let resultsArray = json["results"] as? [[String: Any]] else {
            return .failure(.parseFailure(
                command: "gt hooks sync --json",
                detail: String(
                    localized: "hooks.sync.noResults",
                    defaultValue: "Response missing 'results' array."
                )
            ))
        }

        let results = resultsArray.compactMap { entry -> HookSyncTargetResult? in
            guard let target = entry["target"] as? String else { return nil }
            let statusString = entry["status"] as? String ?? "failed"
            let resultStatus = HookSyncResultStatus(rawValue: statusString) ?? .failed
            let detail = entry["detail"] as? String
            return HookSyncTargetResult(
                target: target,
                resultStatus: resultStatus,
                detail: detail
            )
        }

        return .success(HooksSyncReport(results: results, timestamp: Date()))
    }
}

import Foundation

// MARK: - Convoy Adapter
//
// Read-only adapter over the Gas Town CLI (`gt`) for convoy data.
// Maps `gt convoy list --json` and `gt convoy show <id> --json` into
// domain models that downstream views (cockpit dashboard, detail panel,
// notification routing) can consume without embedding shell invocations
// or JSON parsing in UI code.
//
// Convoy semantics (from deep-research-report.md):
//   - Convoys are persistent, town-level beads (`hq-cv-*`) that track
//     batched work across rigs.
//   - Swarms are ephemeral groupings within a convoy.
//   - A "stranded convoy" has ready work but no polecats assigned — this
//     is an attention-worthy state the operator should act on.
//
// Consumed by: TASK-014 (convoy detail UI), TASK-018 (attention routing),
// and the operator cockpit dashboard.
//
// Design: stateless, value-oriented, injectable environment (same pattern
// as BeadsAdapter and GasTownDiscovery). All models are Equatable + Sendable.

// MARK: - Attention State

/// The attention state of a convoy — signals whether operator action is needed.
///
/// Attention states are derived from convoy data, not stored upstream.
/// The derivation logic lives in `ConvoyAdapter` so all consumers share
/// the same rules.
enum ConvoyAttentionState: String, Equatable, Sendable, CaseIterable {
    /// Normal progress — no operator action required.
    case normal
    /// Stranded — ready (unblocked, open) issues exist but no polecats are assigned.
    case stranded
    /// Blocked — all remaining issues have unresolved blockers.
    case blocked
}

// MARK: - Domain Models

/// Dashboard-ready summary of a convoy from `gt convoy list --json`.
///
/// Contains enough data for the attention dashboard to display status dots,
/// progress, and stranded-work signals without a detail fetch.
struct ConvoySummary: Equatable, Sendable, Identifiable {
    /// Convoy bead ID (e.g. `hq-cv-abc`).
    let id: String
    /// Human-readable title.
    let title: String
    /// Upstream status string (typically `"open"` or `"closed"`).
    let status: String
    /// Total tracked issues in this convoy.
    let totalIssues: Int
    /// Tracked issues with `"closed"` status.
    let completedIssues: Int
    /// Derived attention state for operator triage.
    let attention: ConvoyAttentionState
    /// Number of polecats currently assigned to tracked issues.
    let assignedPolecats: Int
    /// Rig IDs that have tracked issues in this convoy.
    let rigIds: [String]
    /// When the convoy was created (ISO 8601 string from upstream).
    let createdAt: String?
    /// When the convoy was last updated (ISO 8601 string from upstream).
    let updatedAt: String?

    /// Progress as a fraction in [0.0, 1.0].
    var progress: Double {
        guard totalIssues > 0 else { return 0.0 }
        return Double(completedIssues) / Double(totalIssues)
    }

    /// Whether this convoy needs operator attention.
    var needsAttention: Bool {
        attention != .normal
    }
}

/// A tracked issue within a convoy, from `gt convoy show <id> --json`.
struct ConvoyTrackedIssue: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let status: String
    let assignee: String?
    /// The rig this issue belongs to (derived from bead prefix routing).
    let rigId: String?
    let priority: Int
}

/// Full detail for a selected convoy from `gt convoy show <id> --json`.
///
/// Provides the tracked-issue list and progress context needed by the
/// convoy detail view (TASK-014).
struct ConvoyDetail: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let status: String
    let description: String?
    let trackedIssues: [ConvoyTrackedIssue]
    let attention: ConvoyAttentionState
    /// Rig IDs that have tracked issues in this convoy.
    let rigIds: [String]
    let createdAt: String?
    let updatedAt: String?

    var totalIssues: Int { trackedIssues.count }
    var completedIssues: Int { trackedIssues.filter { $0.status == "closed" }.count }

    var progress: Double {
        guard totalIssues > 0 else { return 0.0 }
        return Double(completedIssues) / Double(totalIssues)
    }
}

// MARK: - Error Types

/// Structured error describing why a convoy adapter operation failed.
enum ConvoyAdapterError: Error, Equatable, Sendable {
    /// The `gt` CLI binary could not be found on PATH.
    case gtCLINotFound
    /// The `gt` CLI exited with a non-zero status.
    case cliFailure(command: String, exitCode: Int32, stderr: String)
    /// The CLI produced output that could not be parsed as JSON.
    case parseFailure(command: String, detail: String)
    /// The requested convoy was not found.
    case convoyNotFound(id: String)
}

// MARK: - Load State

/// Wraps a convoy adapter result with explicit status so views can
/// distinguish between "no data yet", "data loaded", and "failed with reason".
enum ConvoyLoadState<T: Equatable & Sendable>: Equatable, Sendable {
    case idle
    case loading
    case loaded(T)
    case failed(ConvoyAdapterError)
}

// MARK: - Refresh Strategy

/// Configures how frequently and under what conditions convoy data
/// should be refreshed. Downstream coordinators (view models, stores)
/// use this to schedule reloads without hardcoding timing.
struct ConvoyRefreshStrategy: Equatable, Sendable {
    /// Minimum interval between automatic refreshes.
    let autoRefreshInterval: TimeInterval
    /// Whether to refresh when the app returns to foreground.
    let refreshOnForeground: Bool

    /// Suitable for an operator monitoring active work — refreshes every
    /// 30 seconds and on foreground return.
    static let operatorDefault = ConvoyRefreshStrategy(
        autoRefreshInterval: 30,
        refreshOnForeground: true
    )

    /// Manual-only refresh — no automatic reloads.
    static let manual = ConvoyRefreshStrategy(
        autoRefreshInterval: .infinity,
        refreshOnForeground: false
    )
}

// MARK: - Adapter

/// Read-only adapter for convoy data from the Gas Town CLI.
///
/// Stateless and value-oriented. Downstream views hold their own
/// `ConvoyLoadState` and call adapter methods to populate it.
/// The adapter derives attention states from raw convoy data so
/// all consumers share consistent stranded/blocked detection.
struct ConvoyAdapter {

    // MARK: - Configuration

    /// Abstraction over environment and CLI access for testability.
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

        static func live(townRootPath: String) -> Environment {
            let env = GasTownCLIRunner.processEnvironment(townRoot: townRootPath)
            return Environment(
                whichGT: { GasTownCLIRunner.resolveGTCLI() },
                runCLI: { executablePath, arguments in
                    GasTownCLIRunner.runProcess(executablePath: executablePath, arguments: arguments, environment: env)
                }
            )
        }
    }

    let environment: Environment

    init(environment: Environment = .live) {
        self.environment = environment
    }

    init(townRootPath: String) {
        self.environment = .live(townRootPath: townRootPath)
    }

    // MARK: - Public API

    /// Load active convoy summaries suitable for the operator dashboard.
    ///
    /// Invokes `gt convoy list --json` and maps each entry into a
    /// `ConvoySummary` with a derived attention state.
    func loadActiveConvoys() -> Result<[ConvoySummary], ConvoyAdapterError> {
        guard let gtPath = environment.whichGT() else {
            return .failure(.gtCLINotFound)
        }

        let result = environment.runCLI(gtPath, ["convoy", "list", "--json"])

        if result.exitCode != 0 {
            let stderr = String(data: result.stderr, encoding: .utf8) ?? ""
            return .failure(.cliFailure(
                command: "gt convoy list --json",
                exitCode: result.exitCode,
                stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }

        guard let array = try? JSONSerialization.jsonObject(with: result.stdout) as? [[String: Any]] else {
            let raw = String(data: result.stdout, encoding: .utf8) ?? "<binary>"
            return .failure(.parseFailure(
                command: "gt convoy list --json",
                detail: String(
                    localized: "convoy.list.parseFailed",
                    defaultValue: "Expected JSON array from 'gt convoy list --json'. Got: \(raw.prefix(200))"
                )
            ))
        }

        let summaries = array.compactMap { parseConvoySummary($0) }
        return .success(summaries)
    }

    /// Load all convoys (including closed) for historical views.
    ///
    /// Invokes `gt convoy list --all --json`.
    func loadAllConvoys() -> Result<[ConvoySummary], ConvoyAdapterError> {
        guard let gtPath = environment.whichGT() else {
            return .failure(.gtCLINotFound)
        }

        let result = environment.runCLI(gtPath, ["convoy", "list", "--all", "--json"])

        if result.exitCode != 0 {
            let stderr = String(data: result.stderr, encoding: .utf8) ?? ""
            return .failure(.cliFailure(
                command: "gt convoy list --all --json",
                exitCode: result.exitCode,
                stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }

        guard let array = try? JSONSerialization.jsonObject(with: result.stdout) as? [[String: Any]] else {
            let raw = String(data: result.stdout, encoding: .utf8) ?? "<binary>"
            return .failure(.parseFailure(
                command: "gt convoy list --all --json",
                detail: String(
                    localized: "convoy.listAll.parseFailed",
                    defaultValue: "Expected JSON array from 'gt convoy list --all --json'. Got: \(raw.prefix(200))"
                )
            ))
        }

        let summaries = array.compactMap { parseConvoySummary($0) }
        return .success(summaries)
    }

    /// Load full detail for a single convoy by ID.
    ///
    /// Invokes `gt convoy show <id> --json` and parses the result into
    /// a `ConvoyDetail` with tracked issues and derived attention state.
    func loadConvoyDetail(id: String) -> Result<ConvoyDetail, ConvoyAdapterError> {
        guard let gtPath = environment.whichGT() else {
            return .failure(.gtCLINotFound)
        }

        let result = environment.runCLI(gtPath, ["convoy", "show", id, "--json"])

        if result.exitCode != 0 {
            let stderr = String(data: result.stderr, encoding: .utf8) ?? ""
            if stderr.contains("not found") || stderr.contains("no such") {
                return .failure(.convoyNotFound(id: id))
            }
            return .failure(.cliFailure(
                command: "gt convoy show \(id) --json",
                exitCode: result.exitCode,
                stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }

        guard let json = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any] else {
            // Some commands return a single-element array.
            if let array = try? JSONSerialization.jsonObject(with: result.stdout) as? [[String: Any]],
               let first = array.first {
                return parseConvoyDetailResult(first, id: id)
            }

            let raw = String(data: result.stdout, encoding: .utf8) ?? "<binary>"
            return .failure(.parseFailure(
                command: "gt convoy show \(id) --json",
                detail: String(
                    localized: "convoy.detail.parseFailed",
                    defaultValue: "Expected JSON from 'gt convoy show'. Got: \(raw.prefix(200))"
                )
            ))
        }

        return parseConvoyDetailResult(json, id: id)
    }

    // MARK: - JSON Parsing

    private func parseConvoySummary(_ json: [String: Any]) -> ConvoySummary? {
        guard let id = json["id"] as? String,
              let title = json["title"] as? String else {
            return nil
        }

        let trackedIssues = json["tracked_issues"] as? [[String: Any]] ?? []
        let totalIssues = (json["total_issues"] as? Int) ?? trackedIssues.count
        let completedIssues = (json["completed_issues"] as? Int)
            ?? trackedIssues.filter { ($0["status"] as? String) == "closed" }.count

        let assignedPolecats = deriveAssignedPolecatCount(from: trackedIssues)
        let rigIds = deriveRigIds(from: trackedIssues)
        let attention = deriveAttentionState(
            status: json["status"] as? String ?? "open",
            trackedIssues: trackedIssues,
            totalIssues: totalIssues,
            completedIssues: completedIssues
        )

        return ConvoySummary(
            id: id,
            title: title,
            status: json["status"] as? String ?? "open",
            totalIssues: totalIssues,
            completedIssues: completedIssues,
            attention: attention,
            assignedPolecats: assignedPolecats,
            rigIds: rigIds,
            createdAt: json["created_at"] as? String,
            updatedAt: json["updated_at"] as? String
        )
    }

    private func parseConvoyDetailResult(
        _ json: [String: Any],
        id requestedId: String
    ) -> Result<ConvoyDetail, ConvoyAdapterError> {
        guard let id = json["id"] as? String,
              let title = json["title"] as? String else {
            return .failure(.parseFailure(
                command: "gt convoy show \(requestedId) --json",
                detail: String(
                    localized: "convoy.detail.modelFailed",
                    defaultValue: "Could not map JSON to ConvoyDetail for convoy '\(requestedId)'."
                )
            ))
        }

        let rawIssues = json["tracked_issues"] as? [[String: Any]] ?? []
        let trackedIssues = rawIssues.compactMap { parseTrackedIssue($0) }
        let rigIds = deriveRigIds(from: rawIssues)
        let attention = deriveAttentionState(
            status: json["status"] as? String ?? "open",
            trackedIssues: rawIssues,
            totalIssues: trackedIssues.count,
            completedIssues: trackedIssues.filter { $0.status == "closed" }.count
        )

        let detail = ConvoyDetail(
            id: id,
            title: title,
            status: json["status"] as? String ?? "open",
            description: json["description"] as? String,
            trackedIssues: trackedIssues,
            attention: attention,
            rigIds: rigIds,
            createdAt: json["created_at"] as? String,
            updatedAt: json["updated_at"] as? String
        )
        return .success(detail)
    }

    private func parseTrackedIssue(_ json: [String: Any]) -> ConvoyTrackedIssue? {
        guard let id = json["id"] as? String,
              let title = json["title"] as? String else {
            return nil
        }

        return ConvoyTrackedIssue(
            id: id,
            title: title,
            status: json["status"] as? String ?? "unknown",
            assignee: json["assignee"] as? String,
            rigId: json["rig_id"] as? String ?? deriveRigId(fromBeadId: id),
            priority: json["priority"] as? Int ?? 0
        )
    }

    // MARK: - Attention State Derivation

    /// Derive the attention state for a convoy from its tracked issues.
    ///
    /// Rules (evaluated in priority order):
    /// 1. Closed convoys are always `.normal`.
    /// 2. If open issues exist that are not blocked and not assigned → `.stranded`.
    /// 3. If all remaining (non-closed) issues are blocked → `.blocked`.
    /// 4. Otherwise → `.normal` (work is progressing).
    private func deriveAttentionState(
        status: String,
        trackedIssues: [[String: Any]],
        totalIssues: Int,
        completedIssues: Int
    ) -> ConvoyAttentionState {
        // Closed convoys need no attention.
        if status == "closed" { return .normal }

        // All done — nothing to flag.
        if totalIssues > 0 && completedIssues >= totalIssues { return .normal }

        let openIssues = trackedIssues.filter { ($0["status"] as? String) != "closed" }
        if openIssues.isEmpty { return .normal }

        let blockedStatuses: Set<String> = ["blocked"]
        let blocked = openIssues.filter { blockedStatuses.contains($0["status"] as? String ?? "") }
        let unblocked = openIssues.filter { !blockedStatuses.contains($0["status"] as? String ?? "") }

        // All remaining issues are blocked — nothing can progress.
        if !openIssues.isEmpty && blocked.count == openIssues.count {
            return .blocked
        }

        // Stranded: unblocked issues exist but none have an assignee with a polecat role.
        let hasAssignedWork = unblocked.contains { issue in
            guard let assignee = issue["assignee"] as? String, !assignee.isEmpty else {
                return false
            }
            // Polecat assignees follow the pattern "<rig>/polecats/<name>".
            return assignee.contains("/polecats/")
        }

        if !unblocked.isEmpty && !hasAssignedWork {
            return .stranded
        }

        return .normal
    }

    /// Count distinct polecats assigned to tracked issues.
    private func deriveAssignedPolecatCount(from issues: [[String: Any]]) -> Int {
        var polecats: Set<String> = []
        for issue in issues {
            if let assignee = issue["assignee"] as? String,
               assignee.contains("/polecats/") {
                polecats.insert(assignee)
            }
        }
        return polecats.count
    }

    /// Extract unique rig IDs from tracked issues.
    private func deriveRigIds(from issues: [[String: Any]]) -> [String] {
        var rigs: Set<String> = []
        for issue in issues {
            if let rigId = issue["rig_id"] as? String {
                rigs.insert(rigId)
            } else if let id = issue["id"] as? String, let derived = deriveRigId(fromBeadId: id) {
                rigs.insert(derived)
            }
        }
        return rigs.sorted()
    }

    /// Derive a rig ID from a bead ID prefix.
    ///
    /// Bead IDs like `gm-abc` map to rig `gmux` via routes.jsonl. This is
    /// a best-effort heuristic for display; the authoritative mapping is
    /// in the Beads routes file. Returns `nil` if no prefix can be extracted.
    private func deriveRigId(fromBeadId id: String) -> String? {
        // Extract the prefix portion (everything up to and including the first hyphen).
        guard let hyphenIndex = id.firstIndex(of: "-") else { return nil }
        let prefix = String(id[...hyphenIndex])
        // The prefix alone is not a rig name, but it is useful for grouping.
        // Return it as-is; downstream consumers with access to routes can resolve
        // the full rig name.
        return prefix.isEmpty ? nil : prefix
    }

}

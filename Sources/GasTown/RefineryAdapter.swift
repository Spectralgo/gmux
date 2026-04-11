import Foundation

// MARK: - Refinery Adapter
//
// Read-only adapter over the Gas Town CLI (`gt`) and `git` for refinery
// merge-queue data. Maps `gt mq list`, `gt refinery status`, and
// `git log --oneline -20 main` into domain models for the Refinery Panel.
//
// Design: stateless, value-oriented, injectable environment (same pattern
// as ConvoyAdapter and BeadsAdapter). All models are Equatable + Sendable.
// All CLI calls run synchronously — callers dispatch to a background queue.

// MARK: - Pipeline Stage

enum MergePipelineStage: String, Codable, Sendable, CaseIterable {
    case polecatDone    // Polecat pushed branch, notified Witness
    case mergeReady     // Witness validated, sent to Refinery
    case building       // Refinery is rebasing + running validation
    case merged         // Success — landed on main
    case failed         // Build/validation failed
    case rework         // Conflict — fresh polecat spawned
    case skipped        // Operator skipped this item
}

// MARK: - Queue Item

struct MergeQueueItem: Identifiable, Equatable, Sendable {
    let id: String                      // Bead ID (e.g. "gm-wisp-6x8")
    let title: String                   // Commit/bead title
    let author: String                  // Original polecat name
    let sourceBranch: String            // e.g. "toast/fix-auth"
    let targetBranch: String            // e.g. "main"
    var stage: MergePipelineStage       // Current pipeline stage
    let fileCount: Int
    let enteredStageAt: Date            // When it entered current stage
    let errorSummary: String?           // If stage == .failed
    let reworkPolecat: String?          // If stage == .rework
    let conflictFileCount: Int?         // If stage == .rework
    var buildProgress: Double?          // 0.0-1.0 if stage == .building
}

// MARK: - History Entry

struct MergeHistoryEntry: Identifiable, Equatable, Sendable {
    let id: String                      // Commit SHA (short)
    let title: String
    let author: String                  // Polecat that produced the work
    let mergedAt: Date
    let beadId: String?                 // Associated bead ID
    let duration: TimeInterval          // Total time from queued to merged
}

// MARK: - Stage Counts

struct PipelineStageCounts: Equatable, Sendable {
    let polecatDone: Int
    let mergeReady: Int
    let building: Int
    let merged: Int
    let failed: Int
    let rework: Int

    var total: Int { polecatDone + mergeReady + building + merged + failed + rework }
}

// MARK: - Refinery Health

enum RefineryHealth: String, Codable, Sendable {
    case patrol         // Watching for MERGE_READY mail
    case processing     // Actively building/merging
    case idle           // Queue empty
    case error          // Agent problem
}

// MARK: - Snapshot

struct RefinerySnapshot: Equatable, Sendable {
    let health: RefineryHealth
    let rigId: String
    let queue: [MergeQueueItem]         // Active items (non-merged, non-skipped)
    let skipped: [MergeQueueItem]       // Operator-skipped items
    let history: [MergeHistoryEntry]    // Recently merged (capped at 20)
    let stageCounts: PipelineStageCounts
}

// MARK: - Error

enum RefineryAdapterError: Error, Equatable, Sendable {
    case gtCLINotFound
    case cliFailure(command: String, exitCode: Int32, stderr: String)
    case parseFailure(command: String, detail: String)
    case refineryNotFound(rigId: String)
}

// MARK: - Load State

enum RefineryLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded(RefinerySnapshot)
    case failed(RefineryAdapterError)
}

// MARK: - Adapter

struct RefineryAdapter: Sendable {

    // MARK: - Configuration

    struct Environment: Sendable {
        var whichGT: @Sendable () -> String?
        var runCLI: @Sendable (_ executablePath: String, _ arguments: [String]) -> GasTownCLIRunner.CLIResult
        var runGit: @Sendable (_ arguments: [String]) -> GasTownCLIRunner.CLIResult

        static let live = Environment(
            whichGT: {
                GasTownCLIRunner.resolveGTCLI()
            },
            runCLI: { executablePath, arguments in
                GasTownCLIRunner.runProcess(executablePath: executablePath, arguments: arguments)
            },
            runGit: { arguments in
                let gitPath = GasTownCLIRunner.resolveExecutable("git") ?? "/usr/bin/git"
                return GasTownCLIRunner.runProcess(executablePath: gitPath, arguments: arguments)
            }
        )
    }

    let environment: Environment

    init(environment: Environment = .live) {
        self.environment = environment
    }

    init(townRootPath: String) {
        self.environment = Environment(
            whichGT: { GasTownCLIRunner.resolveGTCLI() },
            runCLI: { executablePath, arguments in
                GasTownCLIRunner.runProcess(
                    executablePath: executablePath,
                    arguments: arguments,
                    townRootPath: townRootPath
                )
            },
            runGit: { arguments in
                let gitPath = GasTownCLIRunner.resolveExecutable("git") ?? "/usr/bin/git"
                return GasTownCLIRunner.runProcess(executablePath: gitPath, arguments: arguments)
            }
        )
    }

    // MARK: - Public API

    /// Load a complete refinery snapshot for the merge queue. Call from a background queue.
    func loadSnapshot(rigId: String) -> Result<RefinerySnapshot, RefineryAdapterError> {
        guard let gtPath = environment.whichGT() else {
            return .failure(.gtCLINotFound)
        }

        // 1. Load merge queue items
        let queueResult = loadMergeQueue(gtPath: gtPath)

        // 2. Load refinery status
        let health = loadRefineryHealth(gtPath: gtPath)

        // 3. Load recent merge history from git log
        let history = loadMergeHistory()

        switch queueResult {
        case .success(let allItems):
            let active = allItems.filter { $0.stage != .skipped && $0.stage != .merged }
            let skipped = allItems.filter { $0.stage == .skipped }
            let stageCounts = computeStageCounts(from: allItems)

            let snapshot = RefinerySnapshot(
                health: health,
                rigId: rigId,
                queue: active,
                skipped: skipped,
                history: history,
                stageCounts: stageCounts
            )
            return .success(snapshot)

        case .failure(let error):
            return .failure(error)
        }
    }

    // MARK: - CLI Commands

    private func loadMergeQueue(gtPath: String) -> Result<[MergeQueueItem], RefineryAdapterError> {
        let result = environment.runCLI(gtPath, ["mq", "list", "--json"])

        if result.exitCode != 0 {
            let stderr = String(data: result.stderr, encoding: .utf8) ?? ""
            // Empty queue is not an error — some gt versions exit 0 with empty array,
            // others exit 1 with "no items" message.
            if stderr.contains("no items") || stderr.contains("empty") {
                return .success([])
            }
            return .failure(.cliFailure(
                command: "gt mq list --json",
                exitCode: result.exitCode,
                stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }

        // Handle empty output
        let rawString = String(data: result.stdout, encoding: .utf8) ?? ""
        let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "[]" {
            return .success([])
        }

        guard let array = try? JSONSerialization.jsonObject(with: result.stdout) as? [[String: Any]] else {
            return .failure(.parseFailure(
                command: "gt mq list --json",
                detail: String(
                    localized: "refinery.mqList.parseFailed",
                    defaultValue: "Expected JSON array from 'gt mq list --json'. Got: \(trimmed.prefix(200))"
                )
            ))
        }

        let items = array.compactMap { parseMergeQueueItem($0) }
        return .success(items)
    }

    private func loadRefineryHealth(gtPath: String) -> RefineryHealth {
        let result = environment.runCLI(gtPath, ["refinery", "status"])

        guard result.exitCode == 0 else {
            return .error
        }

        let output = (String(data: result.stdout, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if output.contains("processing") || output.contains("building") || output.contains("merging") {
            return .processing
        } else if output.contains("patrol") || output.contains("watching") {
            return .patrol
        } else if output.contains("idle") || output.contains("empty") {
            return .idle
        } else if output.contains("error") || output.contains("failed") {
            return .error
        }

        return .idle
    }

    private func loadMergeHistory() -> [MergeHistoryEntry] {
        let result = environment.runGit(["log", "--oneline", "-20", "main"])

        guard result.exitCode == 0 else {
            return []
        }

        let output = String(data: result.stdout, encoding: .utf8) ?? ""
        let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }

        return lines.prefix(20).compactMap { line -> MergeHistoryEntry? in
            // Format: "abc1234 commit message (issue-id)"
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            let sha = String(parts[0])
            let title = String(parts[1])

            // Try to extract bead ID from parenthetical at end
            let beadId = extractBeadId(from: title)

            // Try to extract author from commit message pattern
            let author = extractAuthor(from: title)

            return MergeHistoryEntry(
                id: sha,
                title: title,
                author: author ?? "unknown",
                mergedAt: Date(),  // git log --oneline doesn't include dates
                beadId: beadId,
                duration: 0
            )
        }
    }

    // MARK: - JSON Parsing

    private func parseMergeQueueItem(_ json: [String: Any]) -> MergeQueueItem? {
        guard let id = json["id"] as? String ?? json["bead_id"] as? String else {
            return nil
        }

        let title = json["title"] as? String ?? json["description"] as? String ?? id
        let author = json["author"] as? String ?? json["polecat"] as? String ?? "unknown"
        let sourceBranch = json["source_branch"] as? String ?? json["branch"] as? String ?? ""
        let targetBranch = json["target_branch"] as? String ?? json["target"] as? String ?? "main"

        let stageString = json["stage"] as? String ?? json["status"] as? String ?? "polecatDone"
        let stage = parseStage(stageString)

        let fileCount = json["file_count"] as? Int ?? json["files"] as? Int ?? 0
        let errorSummary = json["error_summary"] as? String ?? json["error"] as? String
        let reworkPolecat = json["rework_polecat"] as? String
        let conflictFileCount = json["conflict_file_count"] as? Int
        let buildProgress = json["build_progress"] as? Double

        let enteredStageAt: Date
        if let dateString = json["entered_stage_at"] as? String ?? json["updated_at"] as? String {
            enteredStageAt = parseISO8601Date(dateString) ?? Date()
        } else {
            enteredStageAt = Date()
        }

        return MergeQueueItem(
            id: id,
            title: title,
            author: author,
            sourceBranch: sourceBranch,
            targetBranch: targetBranch,
            stage: stage,
            fileCount: fileCount,
            enteredStageAt: enteredStageAt,
            errorSummary: errorSummary,
            reworkPolecat: reworkPolecat,
            conflictFileCount: conflictFileCount,
            buildProgress: buildProgress
        )
    }

    private func parseStage(_ raw: String) -> MergePipelineStage {
        // Try direct rawValue match first
        if let stage = MergePipelineStage(rawValue: raw) {
            return stage
        }
        // Fuzzy match common CLI output variants
        let lower = raw.lowercased()
        switch lower {
        case "polecat_done", "done", "submitted":
            return .polecatDone
        case "merge_ready", "ready", "validated":
            return .mergeReady
        case "building", "rebasing", "testing":
            return .building
        case "merged", "landed":
            return .merged
        case "failed", "error", "rejected":
            return .failed
        case "rework", "conflict":
            return .rework
        case "skipped":
            return .skipped
        default:
            return .polecatDone
        }
    }

    private func parseISO8601Date(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    // MARK: - Helpers

    private func computeStageCounts(from items: [MergeQueueItem]) -> PipelineStageCounts {
        var polecatDone = 0, mergeReady = 0, building = 0, merged = 0, failed = 0, rework = 0
        for item in items {
            switch item.stage {
            case .polecatDone: polecatDone += 1
            case .mergeReady: mergeReady += 1
            case .building: building += 1
            case .merged: merged += 1
            case .failed: failed += 1
            case .rework: rework += 1
            case .skipped: break
            }
        }
        return PipelineStageCounts(
            polecatDone: polecatDone,
            mergeReady: mergeReady,
            building: building,
            merged: merged,
            failed: failed,
            rework: rework
        )
    }

    private func extractBeadId(from title: String) -> String? {
        // Match pattern like "(gm-abc)" or "(hq-xyz)" at end of commit message
        let pattern = "\\(([a-z]+-[a-z0-9]+)\\)\\s*$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let range = Range(match.range(at: 1), in: title) else {
            return nil
        }
        return String(title[range])
    }

    private func extractAuthor(from title: String) -> String? {
        // Some commit messages include author in pattern "by <polecat>"
        let pattern = "\\bby\\s+([a-zA-Z][a-zA-Z0-9_-]*/polecats/[a-zA-Z0-9_-]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let range = Range(match.range(at: 1), in: title) else {
            return nil
        }
        return String(title[range])
    }
}

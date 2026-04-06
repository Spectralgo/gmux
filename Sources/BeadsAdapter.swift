import Foundation

// MARK: - Beads Adapter
//
// Read-only adapter over the Beads CLI (`bd`) and routes file.
// Normalizes Beads output into app models that downstream views
// (convoy, ready-work, bead-detail) can consume without embedding
// shell invocations or JSON parsing in UI code.
//
// Consumed by: TASK-015 (ready-work surface), TASK-016 (bead-detail),
// and convoy-linked issue context.
//
// Design: stateless, value-oriented, injectable environment (same
// pattern as GasTownDiscovery). All models are Equatable + Sendable.

// MARK: - Domain Models

/// A routing rule mapping a bead ID prefix to a rig path.
struct BeadRoute: Equatable, Sendable, Identifiable {
    /// The bead ID prefix (e.g. "gm-", "hq-", "sc-").
    let prefix: String
    /// Relative path from the Town root to the rig directory (e.g. "gmux", ".").
    let path: String

    var id: String { prefix }
}

/// Summary of a bead as returned by `bd ready` or `bd list`.
struct BeadSummary: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let status: String
    let priority: Int
    let issueType: String
    let assignee: String?
    let owner: String?
    let createdAt: String?
    let labels: [String]
    let dependencyCount: Int
    let dependentCount: Int
}

/// A dependency edge between two beads.
struct BeadDependency: Equatable, Sendable {
    let id: String
    let title: String
    let status: String
    let dependencyType: String
}

/// Full detail of a single bead as returned by `bd show <id> --json`.
struct BeadDetail: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let acceptanceCriteria: String?
    let status: String
    let priority: Int
    let issueType: String
    let assignee: String?
    let owner: String?
    let estimatedMinutes: Int?
    let createdAt: String?
    let createdBy: String?
    let updatedAt: String?
    let externalRef: String?
    let dependencies: [BeadDependency]
}

// MARK: - Error Types

/// Structured error describing why a Beads adapter operation failed.
enum BeadsAdapterError: Error, Equatable, Sendable {
    /// The `bd` CLI binary could not be found on PATH.
    case bdCLINotFound
    /// The `bd` CLI exited with a non-zero status.
    case cliFailure(command: String, exitCode: Int32, stderr: String)
    /// The CLI produced output that could not be parsed as JSON.
    case parseFailure(command: String, detail: String)
    /// The routes file could not be read or parsed.
    case routesFileUnreadable(path: String, detail: String)
    /// The requested bead was not found.
    case beadNotFound(id: String)
}

// MARK: - Adapter Result Wrapper

/// Wraps an adapter result with explicit status so views can distinguish
/// between "no data yet", "data loaded", and "failed with reason".
enum BeadsLoadState<T: Equatable & Sendable>: Equatable, Sendable {
    case idle
    case loading
    case loaded(T)
    case failed(BeadsAdapterError)
}

// MARK: - Adapter

/// Read-only adapter for Beads data: routes, ready work, and bead detail.
///
/// Designed as a stateless value-oriented service. Downstream views hold
/// their own `BeadsLoadState` and call adapter methods to populate it.
struct BeadsAdapter {

    // MARK: - Configuration

    /// Abstraction over environment, filesystem, and CLI access for testability.
    struct Environment: Sendable {
        var contentsOfFile: @Sendable (String) -> Data?
        var fileExists: @Sendable (String) -> Bool
        var whichBD: @Sendable () -> String?
        var runCLI: @Sendable (_ executablePath: String, _ arguments: [String]) -> CLIResult

        static let live = Environment(
            contentsOfFile: { path in
                FileManager.default.contents(atPath: path)
            },
            fileExists: { path in
                FileManager.default.fileExists(atPath: path)
            },
            whichBD: {
                BeadsAdapter.resolveBDCLI()
            },
            runCLI: { executablePath, arguments in
                BeadsAdapter.runProcess(executablePath: executablePath, arguments: arguments)
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

    /// Load bead routing rules from the Town's `routes.jsonl` file.
    ///
    /// Each line in routes.jsonl is a JSON object with `prefix` and `path` keys.
    /// This reads the file directly without invoking the CLI.
    func loadRoutes(townRootPath: String) -> Result<[BeadRoute], BeadsAdapterError> {
        let routesPath = (townRootPath as NSString).appendingPathComponent(".beads/routes.jsonl")

        guard environment.fileExists(routesPath) else {
            return .failure(.routesFileUnreadable(
                path: routesPath,
                detail: String(
                    localized: "beads.routes.notFound",
                    defaultValue: "Routes file does not exist at '\(routesPath)'."
                )
            ))
        }

        guard let data = environment.contentsOfFile(routesPath) else {
            return .failure(.routesFileUnreadable(
                path: routesPath,
                detail: String(
                    localized: "beads.routes.unreadable",
                    defaultValue: "Could not read routes file at '\(routesPath)'."
                )
            ))
        }

        guard let content = String(data: data, encoding: .utf8) else {
            return .failure(.routesFileUnreadable(
                path: routesPath,
                detail: String(
                    localized: "beads.routes.encoding",
                    defaultValue: "Routes file is not valid UTF-8."
                )
            ))
        }

        var routes: [BeadRoute] = []
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            guard let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let prefix = json["prefix"] as? String,
                  let path = json["path"] as? String else {
                continue
            }

            routes.append(BeadRoute(prefix: prefix, path: path))
        }

        return .success(routes)
    }

    /// Load beads that are ready to work (no unresolved blockers).
    ///
    /// Invokes `bd ready --json` and parses the result into `BeadSummary` models.
    func loadReadyWork() -> Result<[BeadSummary], BeadsAdapterError> {
        guard let bdPath = environment.whichBD() else {
            return .failure(.bdCLINotFound)
        }

        let result = environment.runCLI(bdPath, ["ready", "--json"])

        if result.exitCode != 0 {
            let stderr = String(data: result.stderr, encoding: .utf8) ?? ""
            return .failure(.cliFailure(
                command: "bd ready --json",
                exitCode: result.exitCode,
                stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }

        guard let array = try? JSONSerialization.jsonObject(with: result.stdout) as? [[String: Any]] else {
            let raw = String(data: result.stdout, encoding: .utf8) ?? "<binary>"
            return .failure(.parseFailure(
                command: "bd ready --json",
                detail: String(
                    localized: "beads.ready.parseFailed",
                    defaultValue: "Expected JSON array from 'bd ready --json'. Got: \(raw.prefix(200))"
                )
            ))
        }

        let summaries = array.compactMap { parseBeadSummary($0) }
        return .success(summaries)
    }

    /// Load full detail for a single bead by ID.
    ///
    /// Invokes `bd show <id> --json` and parses the result into a `BeadDetail`.
    func loadBeadDetail(id: String) -> Result<BeadDetail, BeadsAdapterError> {
        guard let bdPath = environment.whichBD() else {
            return .failure(.bdCLINotFound)
        }

        let result = environment.runCLI(bdPath, ["show", id, "--json"])

        if result.exitCode != 0 {
            let stderr = String(data: result.stderr, encoding: .utf8) ?? ""
            if stderr.contains("not found") || stderr.contains("no such") {
                return .failure(.beadNotFound(id: id))
            }
            return .failure(.cliFailure(
                command: "bd show \(id) --json",
                exitCode: result.exitCode,
                stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }

        // `bd show` returns a JSON array with a single element.
        guard let array = try? JSONSerialization.jsonObject(with: result.stdout) as? [[String: Any]],
              let first = array.first else {
            let raw = String(data: result.stdout, encoding: .utf8) ?? "<binary>"
            return .failure(.parseFailure(
                command: "bd show \(id) --json",
                detail: String(
                    localized: "beads.detail.parseFailed",
                    defaultValue: "Expected JSON array from 'bd show'. Got: \(raw.prefix(200))"
                )
            ))
        }

        guard let detail = parseBeadDetail(first) else {
            return .failure(.parseFailure(
                command: "bd show \(id) --json",
                detail: String(
                    localized: "beads.detail.modelFailed",
                    defaultValue: "Could not map JSON to BeadDetail for bead '\(id)'."
                )
            ))
        }

        return .success(detail)
    }

    // MARK: - JSON Parsing

    private func parseBeadSummary(_ json: [String: Any]) -> BeadSummary? {
        guard let id = json["id"] as? String,
              let title = json["title"] as? String else {
            return nil
        }

        return BeadSummary(
            id: id,
            title: title,
            status: json["status"] as? String ?? "unknown",
            priority: json["priority"] as? Int ?? 0,
            issueType: json["issue_type"] as? String ?? "unknown",
            assignee: json["assignee"] as? String,
            owner: json["owner"] as? String,
            createdAt: json["created_at"] as? String,
            labels: json["labels"] as? [String] ?? [],
            dependencyCount: json["dependency_count"] as? Int ?? 0,
            dependentCount: json["dependent_count"] as? Int ?? 0
        )
    }

    private func parseBeadDetail(_ json: [String: Any]) -> BeadDetail? {
        guard let id = json["id"] as? String,
              let title = json["title"] as? String else {
            return nil
        }

        var dependencies: [BeadDependency] = []
        if let deps = json["dependencies"] as? [[String: Any]] {
            for dep in deps {
                guard let depId = dep["id"] as? String,
                      let depTitle = dep["title"] as? String else {
                    continue
                }
                dependencies.append(BeadDependency(
                    id: depId,
                    title: depTitle,
                    status: dep["status"] as? String ?? "unknown",
                    dependencyType: dep["dependency_type"] as? String ?? "blocks"
                ))
            }
        }

        return BeadDetail(
            id: id,
            title: title,
            description: json["description"] as? String,
            acceptanceCriteria: json["acceptance_criteria"] as? String,
            status: json["status"] as? String ?? "unknown",
            priority: json["priority"] as? Int ?? 0,
            issueType: json["issue_type"] as? String ?? "unknown",
            assignee: json["assignee"] as? String,
            owner: json["owner"] as? String,
            estimatedMinutes: json["estimated_minutes"] as? Int,
            createdAt: json["created_at"] as? String,
            createdBy: json["created_by"] as? String,
            updatedAt: json["updated_at"] as? String,
            externalRef: json["external_ref"] as? String,
            dependencies: dependencies
        )
    }

    // MARK: - CLI Helpers

    /// Attempt to find the `bd` binary on PATH.
    static func resolveBDCLI() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["bd"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let path, !path.isEmpty {
                    return path
                }
            }
        } catch {
            // which not available or failed — bd not on PATH.
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

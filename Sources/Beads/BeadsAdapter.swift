import Foundation
import Combine

// MARK: - Domain Model

/// A dependency reference on a bead.
struct BeadDependency: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let status: BeadStatus?
}

/// Detailed bead information suitable for the inspector view.
/// This single model is reused across convoy, ready-work, and workspace-driven entry points.
struct BeadDetail: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let status: BeadStatus
    let priority: Int?
    let type: String?
    let owner: String?
    let assignee: String?
    let description: String
    let acceptanceCriteria: [String]
    let dependencies: [BeadDependency]
    let createdDate: String?
    let updatedDate: String?
    let externalRef: String?
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
    /// A command failed with output.
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .bdCLINotFound:
            return String(localized: "beadsAdapter.error.cliNotFound", defaultValue: "The 'bd' CLI was not found on PATH.")
        case .cliFailure(let cmd, let code, let stderr):
            return "\(cmd) exited \(code): \(stderr)"
        case .parseFailure(_, let detail):
            return detail
        case .routesFileUnreadable(_, let detail):
            return detail
        case .beadNotFound(let id):
            return String(localized: "beadsAdapter.error.beadNotFound", defaultValue: "Bead '\(id)' not found.")
        case .commandFailed(let output):
            return String(localized: "beadsAdapter.error.commandFailed", defaultValue: "Beads command failed: \(output)")
        }
    }
}

// MARK: - Load State

/// Wraps a beads adapter result with explicit status so views can
/// distinguish between "no data yet", "data loaded", and "failed with reason".
enum BeadsLoadState<T: Equatable & Sendable>: Equatable, Sendable {
    case idle
    case loading
    case loaded(T)
    case failed(BeadsAdapterError)
}

// MARK: - Adapter

/// Fetches bead data via the `bd` CLI tool.
/// Designed as the single read-model adapter for all bead-detail consumers.
@MainActor
final class BeadsAdapter: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private let bdPath: String
    private let townRootPath: String?

    nonisolated init(townRootPath: String? = nil) {
        self.townRootPath = townRootPath
        bdPath = GasTownCLIRunner.resolveExecutable("bd") ?? "bd"
    }

    /// Fetch full bead detail by ID (async).
    func fetchBeadDetail(beadId: String) async -> BeadDetail? {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let output = try await runBdAsync(arguments: ["show", beadId])
            return parseBeadShowOutput(output, beadId: beadId)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Synchronous Result-based API (for ReadyWorkPanel)

    /// Load ready-work beads synchronously. Runs `bd ready --json`.
    /// Must be called from a background queue.
    nonisolated func loadReadyWork() -> Result<[BeadSummary], BeadsAdapterError> {
        let result = runBdSync(arguments: ["ready", "--json"])
        switch result {
        case .failure(let error):
            return .failure(error)
        case .success(let output):
            let summaries = parseReadyWorkOutput(output)
            return .success(summaries)
        }
    }

    /// Load a bead detail synchronously. Runs `bd show <id>`.
    /// Must be called from a background queue.
    nonisolated func loadBeadDetail(id: String) -> Result<BeadDetail, BeadsAdapterError> {
        let result = runBdSync(arguments: ["show", id])
        switch result {
        case .failure(let error):
            return .failure(error)
        case .success(let output):
            if let detail = parseBeadShowOutput(output, beadId: id) {
                return .success(detail)
            } else {
                return .failure(.beadNotFound(id: id))
            }
        }
    }

    // MARK: - CLI execution (async)

    private func runBdAsync(arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [bdPath, townRootPath] in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: bdPath)
                process.arguments = arguments
                process.environment = GasTownCLIRunner.cliEnvironment(townRootPath: townRootPath)

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    if process.terminationStatus != 0 {
                        continuation.resume(throwing: BeadsAdapterError.commandFailed(output))
                    } else {
                        continuation.resume(returning: output)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - CLI execution (sync)

    private nonisolated func runBdSync(arguments: [String]) -> Result<String, BeadsAdapterError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bdPath)
        process.arguments = arguments
        process.environment = GasTownCLIRunner.cliEnvironment(townRootPath: townRootPath)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""

            if process.terminationStatus != 0 {
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                return .failure(.cliFailure(
                    command: "bd \(arguments.joined(separator: " "))",
                    exitCode: process.terminationStatus,
                    stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
            }
            return .success(stdout)
        } catch {
            return .failure(.bdCLINotFound)
        }
    }

    // MARK: - Parsing

    /// Parse `bd ready --json` output into an array of BeadSummary.
    private nonisolated func parseReadyWorkOutput(_ output: String) -> [BeadSummary] {
        guard let data = output.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return array.compactMap { json -> BeadSummary? in
            guard let id = json["id"] as? String,
                  let title = json["title"] as? String else { return nil }

            return BeadSummary(
                id: id,
                title: title,
                status: json["status"] as? String ?? "open",
                priority: json["priority"] as? Int ?? 0,
                issueType: json["type"] as? String ?? "task",
                assignee: json["assignee"] as? String,
                owner: json["owner"] as? String,
                createdAt: json["created_at"] as? String,
                labels: json["labels"] as? [String] ?? [],
                dependencyCount: json["dependency_count"] as? Int ?? 0,
                dependentCount: json["dependent_count"] as? Int ?? 0
            )
        }
    }

    /// Parse the output of `bd show <id>` into a BeadDetail.
    /// The output format is a human-readable block with labeled fields.
    private nonisolated func parseBeadShowOutput(_ output: String, beadId: String) -> BeadDetail? {
        let lines = output.components(separatedBy: "\n")
        guard !lines.isEmpty else { return nil }

        var title = ""
        var status: BeadStatus = .open
        var priority: Int?
        var type: String?
        var owner: String?
        var assignee: String?
        var description = ""
        var acceptanceCriteria: [String] = []
        var dependencies: [BeadDependency] = []
        var createdDate: String?
        var updatedDate: String?
        var externalRef: String?

        enum Section {
            case none, description, acceptance, dependsOn
        }
        var currentSection: Section = .none

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // First line often contains title with status badge
            if trimmed.contains("\u{25C7}") || trimmed.contains("\u{25C6}") {
                if let firstDot = trimmed.range(of: " \u{00B7} ") {
                    let afterFirstDot = trimmed[firstDot.upperBound...]
                    if let bracketRange = afterFirstDot.range(of: "   [") {
                        title = String(afterFirstDot[..<bracketRange.lowerBound])
                    } else {
                        title = String(afterFirstDot)
                    }
                }
                if let bracketStart = trimmed.range(of: "["),
                   let bracketEnd = trimmed.range(of: "]") {
                    let badge = String(trimmed[bracketStart.upperBound..<bracketEnd.lowerBound])
                    let badgeUpper = badge.uppercased()
                    if badgeUpper.contains("HOOKED") { status = .hooked }
                    else if badgeUpper.contains("IN_PROGRESS") || badgeUpper.contains("IN PROGRESS") { status = .inProgress }
                    else if badgeUpper.contains("BLOCKED") { status = .blocked }
                    else if badgeUpper.contains("CLOSED") { status = .closed }
                    else if badgeUpper.contains("DEFERRED") { status = .deferred }
                    else if badgeUpper.contains("PINNED") { status = .pinned }
                    else if badgeUpper.contains("OPEN") { status = .open }
                    if let pRange = badge.range(of: "P", options: .caseInsensitive) {
                        let afterP = badge[pRange.upperBound...]
                        if let digit = afterP.first, digit.isNumber {
                            priority = Int(String(digit))
                        }
                    }
                }
                continue
            }

            // Field lines
            if trimmed.hasPrefix("Owner:") {
                owner = trimmed.replacingOccurrences(of: "Owner:", with: "").trimmingCharacters(in: .whitespaces)
                currentSection = .none
                continue
            }
            if trimmed.hasPrefix("Assignee:") {
                assignee = trimmed.replacingOccurrences(of: "Assignee:", with: "").trimmingCharacters(in: .whitespaces)
                currentSection = .none
                continue
            }
            if trimmed.hasPrefix("Type:") {
                type = trimmed.replacingOccurrences(of: "Type:", with: "").trimmingCharacters(in: .whitespaces)
                currentSection = .none
                continue
            }
            if trimmed.hasPrefix("Created:") {
                createdDate = trimmed.replacingOccurrences(of: "Created:", with: "").trimmingCharacters(in: .whitespaces)
                currentSection = .none
                continue
            }
            if trimmed.hasPrefix("Updated:") {
                updatedDate = trimmed.replacingOccurrences(of: "Updated:", with: "").trimmingCharacters(in: .whitespaces)
                currentSection = .none
                continue
            }
            if trimmed.hasPrefix("External:") {
                externalRef = trimmed.replacingOccurrences(of: "External:", with: "").trimmingCharacters(in: .whitespaces)
                currentSection = .none
                continue
            }

            // Section headers
            if trimmed == "DESCRIPTION" {
                currentSection = .description
                continue
            }
            if trimmed == "ACCEPTANCE CRITERIA" || trimmed.hasPrefix("ACCEPTANCE") {
                currentSection = .acceptance
                continue
            }
            if trimmed == "DEPENDS ON" || trimmed.hasPrefix("DEPENDS") {
                currentSection = .dependsOn
                continue
            }

            // Section content
            switch currentSection {
            case .description:
                if !trimmed.isEmpty {
                    if !description.isEmpty { description += "\n" }
                    description += trimmed
                }
            case .acceptance:
                if !trimmed.isEmpty {
                    acceptanceCriteria.append(trimmed)
                }
            case .dependsOn:
                if trimmed.hasPrefix("\u{2192}") || trimmed.hasPrefix("->") {
                    let cleaned = trimmed
                        .replacingOccurrences(of: "\u{2192}", with: "")
                        .replacingOccurrences(of: "->", with: "")
                        .replacingOccurrences(of: "\u{25CB}", with: "")
                        .replacingOccurrences(of: "\u{25CF}", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    if let colonRange = cleaned.range(of: ":") {
                        let depId = String(cleaned[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                        let depTitle = String(cleaned[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                        dependencies.append(BeadDependency(id: depId, title: depTitle, status: nil))
                    }
                }
            case .none:
                break
            }
        }

        if title.isEmpty {
            title = beadId
        }

        return BeadDetail(
            id: beadId,
            title: title,
            status: status,
            priority: priority,
            type: type,
            owner: owner,
            assignee: assignee,
            description: description,
            acceptanceCriteria: acceptanceCriteria,
            dependencies: dependencies,
            createdDate: createdDate,
            updatedDate: updatedDate,
            externalRef: externalRef
        )
    }
}

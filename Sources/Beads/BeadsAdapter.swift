import Foundation
import Combine

// MARK: - Domain Model

/// Status of a bead in the Beads tracking system.
enum BeadStatus: String, Codable, Sendable {
    case open
    case inProgress = "in_progress"
    case blocked
    case deferred
    case closed
    case pinned
    case hooked

    var displayLabel: String {
        switch self {
        case .open: return String(localized: "beadStatus.open", defaultValue: "Open")
        case .inProgress: return String(localized: "beadStatus.inProgress", defaultValue: "In Progress")
        case .blocked: return String(localized: "beadStatus.blocked", defaultValue: "Blocked")
        case .deferred: return String(localized: "beadStatus.deferred", defaultValue: "Deferred")
        case .closed: return String(localized: "beadStatus.closed", defaultValue: "Closed")
        case .pinned: return String(localized: "beadStatus.pinned", defaultValue: "Pinned")
        case .hooked: return String(localized: "beadStatus.hooked", defaultValue: "Hooked")
        }
    }

    var iconName: String {
        switch self {
        case .open: return "circle"
        case .inProgress: return "circle.dotted.circle"
        case .blocked: return "exclamationmark.circle"
        case .deferred: return "clock"
        case .closed: return "checkmark.circle"
        case .pinned: return "pin.circle"
        case .hooked: return "arrow.right.circle"
        }
    }

    var accentColorName: String {
        switch self {
        case .open: return "systemGray"
        case .inProgress: return "systemBlue"
        case .blocked: return "systemRed"
        case .deferred: return "systemOrange"
        case .closed: return "systemGreen"
        case .pinned: return "systemPurple"
        case .hooked: return "systemTeal"
        }
    }
}

/// A dependency reference on a bead.
struct BeadDependency: Identifiable, Sendable {
    let id: String
    let title: String
    let status: BeadStatus?
}

/// Detailed bead information suitable for the inspector view.
/// This single model is reused across convoy, ready-work, and workspace-driven entry points.
struct BeadDetail: Identifiable, Sendable {
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

// MARK: - Adapter

/// Fetches bead data via the `bd` CLI tool.
/// Designed as the single read-model adapter for all bead-detail consumers.
@MainActor
final class BeadsAdapter: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private let bdPath: String

    init() {
        // Resolve bd from common locations
        if FileManager.default.fileExists(atPath: "/usr/local/bin/bd") {
            bdPath = "/usr/local/bin/bd"
        } else if let home = ProcessInfo.processInfo.environment["HOME"] {
            let localBd = "\(home)/.local/bin/bd"
            if FileManager.default.fileExists(atPath: localBd) {
                bdPath = localBd
            } else {
                bdPath = "bd"
            }
        } else {
            bdPath = "bd"
        }
    }

    /// Fetch full bead detail by ID.
    func fetchBeadDetail(beadId: String) async -> BeadDetail? {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let output = try await runBd(arguments: ["show", beadId])
            return parseBeadShowOutput(output, beadId: beadId)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: - CLI execution

    private func runBd(arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [bdPath] in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: bdPath)
                process.arguments = arguments

                // Inherit PATH so bd can find dolt
                var env = ProcessInfo.processInfo.environment
                if let path = env["PATH"] {
                    env["PATH"] = path
                }
                process.environment = env

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

    // MARK: - Parsing

    /// Parse the output of `bd show <id>` into a BeadDetail.
    /// The output format is a human-readable block with labeled fields.
    private func parseBeadShowOutput(_ output: String, beadId: String) -> BeadDetail? {
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
            // e.g. "◇ gm-0j7 · TASK-016: Build bead inspector...   [● P2 · HOOKED]"
            if trimmed.contains("◇") || trimmed.contains("◆") {
                // Extract title between "· " markers
                if let firstDot = trimmed.range(of: " · ") {
                    let afterFirstDot = trimmed[firstDot.upperBound...]
                    if let bracketRange = afterFirstDot.range(of: "   [") {
                        title = String(afterFirstDot[..<bracketRange.lowerBound])
                    } else {
                        title = String(afterFirstDot)
                    }
                }
                // Extract status from bracket
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
                    // Extract priority
                    if let pRange = badge.range(of: "P", options: .caseInsensitive) {
                        let afterP = badge[pRange.upperBound...]
                        if let digit = afterP.first, digit.isNumber {
                            priority = Int(String(digit))
                        }
                    }
                }
                continue
            }

            // Field lines: "Key: Value"
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
                // Lines like "  → ○ gm-wisp-0jr0: (EPIC) mol-polecat-work ● P2"
                if trimmed.hasPrefix("→") || trimmed.hasPrefix("->") {
                    let cleaned = trimmed
                        .replacingOccurrences(of: "→", with: "")
                        .replacingOccurrences(of: "->", with: "")
                        .replacingOccurrences(of: "○", with: "")
                        .replacingOccurrences(of: "●", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    // Extract ID and title
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

        // If we couldn't parse a title, use the bead ID
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

enum BeadsAdapterError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let output):
            return String(
                localized: "beadsAdapter.error.commandFailed",
                defaultValue: "Beads command failed: \(output)"
            )
        }
    }
}

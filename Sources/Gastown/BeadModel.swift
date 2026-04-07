import Foundation

/// Valid bead statuses as defined by the Beads system.
enum BeadStatus: String, Codable, Sendable, CaseIterable {
    case open
    case inProgress = "in_progress"
    case blocked
    case deferred
    case closed
    case pinned
    case hooked
}

/// Valid bead types.
enum BeadType: String, Codable, Sendable {
    case bug
    case feature
    case task
    case epic
    case chore
    case decision
}

/// A bead as returned by `bd show <id> --json`.
///
/// Parsed from the JSON array output. Only the fields relevant to
/// display and write flows are decoded; unknown keys are ignored.
struct WritableBeadDetail: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let acceptanceCriteria: String?
    let status: BeadStatus
    let priority: Int?
    let issueType: BeadType?
    let assignee: String?
    let owner: String?
    let estimatedMinutes: Int?
    let createdAt: String?
    let updatedAt: String?
    let externalRef: String?
    let notes: String?
    let design: String?

    enum CodingKeys: String, CodingKey {
        case id, title, description
        case acceptanceCriteria = "acceptance_criteria"
        case status, priority
        case issueType = "issue_type"
        case assignee, owner
        case estimatedMinutes = "estimated_minutes"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case externalRef = "external_ref"
        case notes, design
    }
}

/// The outcome of a bead write operation.
enum BeadWriteOutcome: Sendable {
    case idle
    case inFlight
    case succeeded(WritableBeadDetail?)
    case failed(String)
}

/// Parse a `bd show <id> --json` response into a `WritableBeadDetail`.
enum BeadModelParser {

    static func parseWritableDetail(from json: String) -> WritableBeadDetail? {
        guard let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        // bd show --json returns an array; take the first element.
        if let array = try? decoder.decode([WritableBeadDetail].self, from: data),
           let first = array.first {
            return first
        }
        // Fall back to single-object parse.
        return try? decoder.decode(WritableBeadDetail.self, from: data)
    }
}

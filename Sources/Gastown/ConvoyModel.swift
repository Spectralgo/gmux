import Foundation

/// A tracked issue within a convoy.
struct ConvoyTrackedIssue: Codable, Sendable, Identifiable {
    let id: String
    let title: String?
    let status: String?
    let prefix: String?

    enum CodingKeys: String, CodingKey {
        case id, title, status, prefix
    }
}

/// Convoy detail as returned by `gt convoy status <id> --json`.
struct ConvoyDetail: Codable, Sendable, Identifiable {
    let id: String
    let name: String?
    let status: String?
    let trackedIssues: [ConvoyTrackedIssue]?
    let subscriberCount: Int?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, status
        case trackedIssues = "tracked_issues"
        case subscriberCount = "subscriber_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// The outcome of a convoy write operation.
enum ConvoyWriteOutcome: Sendable {
    case idle
    case inFlight
    case succeeded(ConvoyDetail?)
    case failed(String)
}

/// Parse `gt convoy status <id> --json` output.
enum ConvoyModelParser {

    static func parseDetail(from json: String) -> ConvoyDetail? {
        guard let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        // Try array first (consistent with bd pattern), then single object.
        if let array = try? decoder.decode([ConvoyDetail].self, from: data),
           let first = array.first {
            return first
        }
        return try? decoder.decode(ConvoyDetail.self, from: data)
    }
}

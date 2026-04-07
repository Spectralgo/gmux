import Foundation

/// The outcome of a convoy write operation.
enum ConvoyWriteOutcome: Sendable {
    case idle
    case inFlight
    case succeeded(ConvoyDetail?)
    case failed(String)
}

/// Parse `gt convoy status <id> --json` output into domain models.
enum ConvoyModelParser {

    static func parseDetail(from json: String) -> ConvoyDetail? {
        guard let data = json.data(using: .utf8) else { return nil }

        let parsed: [String: Any]?
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            parsed = dict
        } else if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let first = array.first {
            parsed = first
        } else {
            parsed = nil
        }

        guard let json = parsed,
              let id = json["id"] as? String,
              let title = json["title"] as? String else {
            return nil
        }

        let rawIssues = json["tracked_issues"] as? [[String: Any]] ?? []
        let trackedIssues = rawIssues.compactMap { parseTrackedIssue($0) }

        let status = json["status"] as? String ?? "open"
        let rigIds = deriveRigIds(from: rawIssues)
        let attention = deriveAttentionState(
            status: status,
            trackedIssues: rawIssues,
            totalIssues: trackedIssues.count,
            completedIssues: trackedIssues.filter { $0.status == "closed" }.count
        )

        return ConvoyDetail(
            id: id,
            title: title,
            status: status,
            description: json["description"] as? String,
            trackedIssues: trackedIssues,
            attention: attention,
            rigIds: rigIds,
            createdAt: json["created_at"] as? String,
            updatedAt: json["updated_at"] as? String
        )
    }

    private static func parseTrackedIssue(_ json: [String: Any]) -> ConvoyTrackedIssue? {
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

    private static func deriveRigIds(from issues: [[String: Any]]) -> [String] {
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

    private static func deriveRigId(fromBeadId id: String) -> String? {
        guard let hyphenIndex = id.firstIndex(of: "-") else { return nil }
        let prefix = String(id[...hyphenIndex])
        return prefix.isEmpty ? nil : prefix
    }

    private static func deriveAttentionState(
        status: String,
        trackedIssues: [[String: Any]],
        totalIssues: Int,
        completedIssues: Int
    ) -> ConvoyAttentionState {
        if status == "closed" { return .normal }
        if totalIssues > 0 && completedIssues >= totalIssues { return .normal }

        let openIssues = trackedIssues.filter { ($0["status"] as? String) != "closed" }
        if openIssues.isEmpty { return .normal }

        let blockedStatuses: Set<String> = ["blocked"]
        let blocked = openIssues.filter { blockedStatuses.contains($0["status"] as? String ?? "") }
        let unblocked = openIssues.filter { !blockedStatuses.contains($0["status"] as? String ?? "") }

        if !openIssues.isEmpty && blocked.count == openIssues.count {
            return .blocked
        }

        let hasAssignedWork = unblocked.contains { issue in
            guard let assignee = issue["assignee"] as? String, !assignee.isEmpty else {
                return false
            }
            return assignee.contains("/polecats/")
        }

        if !unblocked.isEmpty && !hasAssignedWork {
            return .stranded
        }

        return .normal
    }
}

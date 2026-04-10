import Foundation

/// A derived skill category for an agent, computed from bead history.
struct AgentSkill: Identifiable, Equatable, Sendable {
    var id: String { category }

    let category: String
    let taskCount: Int
    let successRate: Double

    /// Derive skills from bead history.
    ///
    /// Priority: explicit label → issue type fallback.
    /// Returns top 6 sorted by task count descending.
    static func derive(from beads: [BeadSummary]) -> [AgentSkill] {
        var buckets: [String: [BeadSummary]] = [:]

        for bead in beads {
            let category = categorize(bead)
            buckets[category, default: []].append(bead)
        }

        var skills: [AgentSkill] = buckets.map { category, beads in
            let closed = beads.filter { $0.status == "closed" }
            let failed = beads.filter { $0.status == "blocked" || $0.status == "deferred" }
            let total = closed.count + failed.count
            let rate = total > 0 ? Double(closed.count) / Double(total) : 0.0

            return AgentSkill(
                category: category,
                taskCount: beads.count,
                successRate: rate
            )
        }

        skills.sort { $0.taskCount > $1.taskCount }
        return Array(skills.prefix(6))
    }

    // MARK: - Categorization

    private static let labelMapping: [String: String] = [
        "ui": "Swift UI",
        "frontend": "Swift UI",
        "panel": "Panel Work",
        "infra": "Infrastructure",
        "ci": "CI/Build",
        "test": "Testing",
        "docs": "Documentation",
        "refactor": "Refactoring",
        "design": "Design",
        "socket": "Socket/CLI",
        "api": "API",
    ]

    private static let typeMapping: [String: String] = [
        "bug": "Bug Fixes",
        "feature": "Feature Work",
        "task": "General Tasks",
        "chore": "Maintenance",
        "epic": "Epics",
    ]

    private static func categorize(_ bead: BeadSummary) -> String {
        // 1. Explicit label match
        for label in bead.labels {
            if let category = labelMapping[label.lowercased()] {
                return category
            }
        }

        // 2. Issue type match
        if let category = typeMapping[bead.issueType.lowercased()] {
            return category
        }

        return "General Tasks"
    }
}

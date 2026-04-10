import Foundation

/// Summary statistics for an agent, computed from their bead history.
struct AgentStats: Equatable, Sendable {
    let tasksCompleted: Int
    let successRate: Double
    let totalBeads: Int
    let openBeads: Int
    let blockedBeads: Int
    let avgPriority: Double
    let labelCount: Int
    let dependencyTotal: Int

    /// Compute stats from a list of bead summaries.
    static func compute(from beads: [BeadSummary]) -> AgentStats {
        let closed = beads.filter { $0.status == "closed" }
        let blocked = beads.filter { $0.status == "blocked" }
        let open = beads.filter { $0.status == "open" || $0.status == "in_progress" || $0.status == "hooked" }
        let deferred = beads.filter { $0.status == "deferred" }

        let denominator = closed.count + blocked.count + deferred.count
        let successRate = denominator > 0 ? Double(closed.count) / Double(denominator) : 0.0

        let priorities = beads.map(\.priority).filter { $0 > 0 }
        let avgPriority = priorities.isEmpty ? 0.0 : Double(priorities.reduce(0, +)) / Double(priorities.count)

        let allLabels = Set(beads.flatMap(\.labels))
        let depTotal = beads.reduce(0) { $0 + $1.dependencyCount }

        return AgentStats(
            tasksCompleted: closed.count,
            successRate: successRate,
            totalBeads: beads.count,
            openBeads: open.count,
            blockedBeads: blocked.count,
            avgPriority: avgPriority,
            labelCount: allLabels.count,
            dependencyTotal: depTotal
        )
    }
}

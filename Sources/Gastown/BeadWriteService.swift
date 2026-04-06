import Foundation
import Combine

/// Service for bead write operations (update and close).
///
/// Wraps the `bd update` and `bd close` CLI commands, runs them as
/// subprocesses, and refreshes the bead read model after each
/// successful mutation.
@MainActor
final class BeadWriteService: ObservableObject {

    /// Current state of the last write operation.
    @Published private(set) var outcome: BeadWriteOutcome = .idle

    /// The most recently refreshed bead detail after a successful write.
    @Published private(set) var lastRefreshedBead: BeadDetail?

    // MARK: - Update Status

    /// Update a bead's status.
    ///
    /// Runs `bd update <id> --status <status>` then refreshes the read model.
    func updateStatus(beadID: String, to status: BeadStatus) async {
        outcome = .inFlight
        let result = await GastownCommandRunner.bd([
            "update", beadID,
            "--status", status.rawValue,
        ])
        await handleWriteResult(result, beadID: beadID)
    }

    // MARK: - Update Notes

    /// Append notes to a bead.
    ///
    /// Runs `bd update <id> --notes "<notes>"`.
    func updateNotes(beadID: String, notes: String) async {
        outcome = .inFlight
        let result = await GastownCommandRunner.bd([
            "update", beadID,
            "--notes", notes,
        ])
        await handleWriteResult(result, beadID: beadID)
    }

    // MARK: - Close

    /// Close a bead with an optional reason.
    ///
    /// Runs `bd close <id>` or `bd close <id> --reason "<reason>"`.
    func close(beadID: String, reason: String? = nil) async {
        outcome = .inFlight
        var args = ["close", beadID]
        if let reason, !reason.isEmpty {
            args += ["--reason", reason]
        }
        let result = await GastownCommandRunner.bd(args)
        await handleWriteResult(result, beadID: beadID)
    }

    // MARK: - Read Model Refresh

    /// Refresh a single bead's detail from the Beads system.
    ///
    /// Runs `bd show <id> --json` and parses the result.
    func refreshBead(id: String) async -> BeadDetail? {
        let result = await GastownCommandRunner.bd(["show", id, "--json"])
        guard result.succeeded else { return nil }
        let detail = BeadModelParser.parseDetail(from: result.stdout)
        if let detail {
            lastRefreshedBead = detail
        }
        return detail
    }

    // MARK: - Private

    private func handleWriteResult(_ result: GastownCommandResult, beadID: String) async {
        guard result.succeeded else {
            let message = result.timedOut
                ? String(
                    localized: "gastown.bead.write.timeout",
                    defaultValue: "Command timed out"
                )
                : result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            outcome = .failed(message.isEmpty ? String(
                localized: "gastown.bead.write.unknownError",
                defaultValue: "Unknown error"
            ) : message)
            return
        }

        // Refresh the read model after a successful write.
        let detail = await refreshBead(id: beadID)
        outcome = .succeeded(detail)
    }
}

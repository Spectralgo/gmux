import Foundation
import Combine

/// Service for convoy write operations (tracked-work management).
///
/// Wraps the `gt convoy add` CLI command, runs it as a subprocess,
/// and refreshes the convoy read model after a successful mutation.
@MainActor
final class ConvoyWriteService: ObservableObject {

    /// Current state of the last write operation.
    @Published private(set) var outcome: ConvoyWriteOutcome = .idle

    /// The most recently refreshed convoy detail after a successful write.
    @Published private(set) var lastRefreshedConvoy: ConvoyDetail?

    // MARK: - Add Tracked Work

    /// Add one or more issues to an existing convoy.
    ///
    /// Runs `gt convoy add <convoyID> <issueIDs...>`.
    /// Reopens the convoy automatically if it was closed.
    func addTrackedWork(convoyID: String, issueIDs: [String]) async {
        guard !issueIDs.isEmpty else {
            outcome = .failed(String(
                localized: "gastown.convoy.write.noIssues",
                defaultValue: "No issues specified"
            ))
            return
        }
        outcome = .inFlight
        var args = ["convoy", "add", convoyID]
        args.append(contentsOf: issueIDs)
        let result = await GastownCommandRunner.gt(args)
        await handleWriteResult(result, convoyID: convoyID)
    }

    // MARK: - Read Model Refresh

    /// Refresh a convoy's detail from the Gastown system.
    ///
    /// Runs `gt convoy status <id> --json` and parses the result.
    func refreshConvoy(id: String) async -> ConvoyDetail? {
        let result = await GastownCommandRunner.gt(["convoy", "status", id, "--json"])
        guard result.succeeded else { return nil }
        let detail = ConvoyModelParser.parseDetail(from: result.stdout)
        if let detail {
            lastRefreshedConvoy = detail
        }
        return detail
    }

    // MARK: - Private

    private func handleWriteResult(_ result: GastownCommandResult, convoyID: String) async {
        guard result.succeeded else {
            let message = result.timedOut
                ? String(
                    localized: "gastown.convoy.write.timeout",
                    defaultValue: "Command timed out"
                )
                : result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            outcome = .failed(message.isEmpty ? String(
                localized: "gastown.convoy.write.unknownError",
                defaultValue: "Unknown error"
            ) : message)
            return
        }

        // Refresh the read model after a successful write.
        let detail = await refreshConvoy(id: convoyID)
        outcome = .succeeded(detail)
    }
}

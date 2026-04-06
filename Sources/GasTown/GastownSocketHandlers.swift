import Foundation

// MARK: - Gastown Socket Handlers
//
// Socket command handlers for the `gastown.*`, `beads.*`, and
// `gmux.open.*` namespaces. These expose Gastown-native cockpit
// features to CLI and automation consumers.
//
// Threading policy:
// - All commands run off-main via GastownCommandRunner subprocesses.
//   The DispatchSemaphore bridge in TerminalController.v2GastownAsync
//   blocks the socket client thread (never the main thread).
// - No command in this file calls v2MainSync or touches AppKit state.
//
// Focus policy:
// - `gmux.open.*` commands are listed in focusIntentV2Methods so the
//   socket focus policy can gate their activation side-effects.
// - All other gastown/beads commands do NOT change focus.

/// Namespace for Gastown/Beads socket handler implementations.
///
/// These are stateless functions that produce `Result` values.
/// The dispatch layer in `TerminalController` translates them into
/// the V2CallResult encoding via the `v2GastownAsync` bridge.
enum GastownSocketHandlers {

    /// Result type mirroring V2CallResult without coupling to TerminalController.
    enum Result {
        case ok([String: Any])
        case err(code: String, message: String)
    }

    // MARK: - gmux.open.by_agent

    /// Open a workspace by Gas Town agent address.
    ///
    /// Resolves the agent address to a worktree path by parsing the
    /// address and constructing the expected Gas Town filesystem path.
    ///
    /// Params:
    ///   - `address` (String, required): Slash-separated agent address
    ///     (e.g. `"gmux/polecats/chrome"`).
    ///   - `focus` (Bool, optional, default true): Whether to activate
    ///     the window and focus the workspace.
    ///
    /// Focus-intent: YES when `focus` is true.
    static func openByAgent(params: [String: Any]) async -> Result {
        guard let address = trimmedString(params, "address") else {
            return .err(code: "invalid_params", message: "Missing or empty 'address' parameter")
        }

        let focus = (params["focus"] as? Bool) ?? true

        // Resolve the agent address to a worktree path via gt CLI
        let cmdResult = await GastownCommandRunner.gt(["worktree", "resolve", address, "--json"])

        var result: [String: Any] = [
            "address": address,
            "focus": focus,
        ]

        if cmdResult.succeeded,
           let data = cmdResult.stdout.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            result.merge(json) { _, new in new }
        } else {
            // Fallback: construct path from convention
            let components = address.split(separator: "/").map(String.init)
            result["resolved"] = false
            result["address_components"] = components
        }

        return .ok(result)
    }

    // MARK: - gmux.open.by_bead

    /// Open a workspace by bead ID.
    ///
    /// Fetches the bead detail to find its assignee, then resolves the
    /// assignee's worktree path.
    ///
    /// Params:
    ///   - `bead_id` (String, required): The bead identifier (e.g. `"gm-3rs"`).
    ///   - `focus` (Bool, optional, default true): Whether to activate
    ///     the window and focus the workspace.
    ///
    /// Focus-intent: YES when `focus` is true.
    static func openByBead(params: [String: Any]) async -> Result {
        guard let beadID = trimmedString(params, "bead_id") else {
            return .err(code: "invalid_params", message: "Missing or empty 'bead_id' parameter")
        }

        let focus = (params["focus"] as? Bool) ?? true

        // Fetch bead detail to get assignee
        let showResult = await GastownCommandRunner.bd(["show", beadID, "--json"])
        guard showResult.succeeded else {
            let msg = showResult.timedOut ? "Timed out fetching bead" : showResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .err(code: "bead_not_found", message: msg.isEmpty ? "Bead '\(beadID)' not found" : msg)
        }

        guard let detail = BeadModelParser.parseWritableDetail(from: showResult.stdout) else {
            return .err(code: "parse_error", message: "Failed to parse bead detail for '\(beadID)'")
        }

        var result: [String: Any] = [
            "bead_id": beadID,
            "title": detail.title,
            "status": detail.status.rawValue,
            "focus": focus,
            "assignee": detail.assignee ?? NSNull(),
        ]

        // If the bead has an assignee, attempt to resolve the worktree
        if let assigneeAddress = detail.assignee, !assigneeAddress.isEmpty {
            let resolveResult = await GastownCommandRunner.gt(["worktree", "resolve", assigneeAddress, "--json"])
            if resolveResult.succeeded,
               let data = resolveResult.stdout.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                result["worktree"] = json
            }
        }

        return .ok(result)
    }

    // MARK: - gmux.open.by_convoy

    /// Open a workspace by convoy ID.
    ///
    /// Fetches the convoy detail, finds its first actionable tracked bead,
    /// and resolves the assignee's worktree path.
    ///
    /// Params:
    ///   - `convoy_id` (String, required): The convoy identifier.
    ///   - `focus` (Bool, optional, default true): Whether to activate
    ///     the window and focus the workspace.
    ///
    /// Focus-intent: YES when `focus` is true.
    static func openByConvoy(params: [String: Any]) async -> Result {
        guard let convoyID = trimmedString(params, "convoy_id") else {
            return .err(code: "invalid_params", message: "Missing or empty 'convoy_id' parameter")
        }

        let focus = (params["focus"] as? Bool) ?? true

        // Fetch convoy detail
        let statusResult = await GastownCommandRunner.gt(["convoy", "status", convoyID, "--json"])
        guard statusResult.succeeded else {
            let msg = statusResult.timedOut ? "Timed out fetching convoy" : statusResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .err(code: "convoy_not_found", message: msg.isEmpty ? "Convoy '\(convoyID)' not found" : msg)
        }

        guard let detail = ConvoyModelParser.parseDetail(from: statusResult.stdout) else {
            return .err(code: "parse_error", message: "Failed to parse convoy detail for '\(convoyID)'")
        }

        var result: [String: Any] = [
            "convoy_id": convoyID,
            "name": detail.name ?? NSNull(),
            "status": detail.status ?? NSNull(),
            "focus": focus,
            "tracked_issue_count": detail.trackedIssues?.count ?? 0,
        ]

        if let tracked = detail.trackedIssues {
            result["tracked_issues"] = tracked.map { issue -> [String: Any] in
                var d: [String: Any] = ["id": issue.id]
                d["title"] = issue.title ?? NSNull()
                d["status"] = issue.status ?? NSNull()
                return d
            }
        }

        return .ok(result)
    }

    // MARK: - beads.show

    /// Show detail for a single bead.
    ///
    /// Params:
    ///   - `bead_id` (String, required): The bead identifier.
    ///
    /// Focus-intent: NO.
    static func beadsShow(params: [String: Any]) async -> Result {
        guard let beadID = trimmedString(params, "bead_id") else {
            return .err(code: "invalid_params", message: "Missing or empty 'bead_id' parameter")
        }

        let cmdResult = await GastownCommandRunner.bd(["show", beadID, "--json"])
        guard cmdResult.succeeded else {
            let msg = cmdResult.timedOut ? "Timed out" : cmdResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .err(code: "bead_not_found", message: msg.isEmpty ? "Bead '\(beadID)' not found" : msg)
        }

        guard let detail = BeadModelParser.parseWritableDetail(from: cmdResult.stdout) else {
            return .err(code: "parse_error", message: "Failed to parse bead '\(beadID)'")
        }

        return .ok(beadDetailDict(detail))
    }

    // MARK: - beads.ready

    /// List beads that are ready to work (no unresolved blockers).
    ///
    /// Params:
    ///   - `rig` (String, optional): Filter by rig name.
    ///
    /// Focus-intent: NO.
    static func beadsReady(params: [String: Any]) async -> Result {
        var args = ["ready", "--json"]
        if let rig = trimmedString(params, "rig") {
            args.append(contentsOf: ["--rig", rig])
        }

        let cmdResult = await GastownCommandRunner.bd(args)
        guard cmdResult.succeeded else {
            let msg = cmdResult.timedOut ? "Timed out" : cmdResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .err(code: "command_failed", message: msg.isEmpty ? "bd ready failed" : msg)
        }

        guard let data = cmdResult.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return .ok(["beads": [] as [Any]])
        }

        return .ok(["beads": json])
    }

    // MARK: - beads.list

    /// List beads with optional status filter.
    ///
    /// Params:
    ///   - `status` (String, optional): Filter by status.
    ///   - `rig` (String, optional): Filter by rig name.
    ///
    /// Focus-intent: NO.
    static func beadsList(params: [String: Any]) async -> Result {
        var args = ["list", "--json"]
        if let status = trimmedString(params, "status") {
            args.append(contentsOf: ["--status", status])
        }
        if let rig = trimmedString(params, "rig") {
            args.append(contentsOf: ["--rig", rig])
        }

        let cmdResult = await GastownCommandRunner.bd(args)
        guard cmdResult.succeeded else {
            let msg = cmdResult.timedOut ? "Timed out" : cmdResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .err(code: "command_failed", message: msg.isEmpty ? "bd list failed" : msg)
        }

        guard let data = cmdResult.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return .ok(["beads": [] as [Any]])
        }

        return .ok(["beads": json])
    }

    // MARK: - beads.update

    /// Update a bead's status or notes.
    ///
    /// Params:
    ///   - `bead_id` (String, required): The bead identifier.
    ///   - `status` (String, optional): New status value.
    ///   - `notes` (String, optional): Notes to append.
    ///
    /// Focus-intent: NO.
    static func beadsUpdate(params: [String: Any]) async -> Result {
        guard let beadID = trimmedString(params, "bead_id") else {
            return .err(code: "invalid_params", message: "Missing or empty 'bead_id' parameter")
        }

        let status = trimmedString(params, "status")
        let notes = trimmedString(params, "notes")

        guard status != nil || notes != nil else {
            return .err(code: "invalid_params", message: "At least one of 'status' or 'notes' is required")
        }

        var args = ["update", beadID]
        if let status {
            args.append(contentsOf: ["--status", status])
        }
        if let notes {
            args.append(contentsOf: ["--notes", notes])
        }

        let cmdResult = await GastownCommandRunner.bd(args)
        guard cmdResult.succeeded else {
            let msg = cmdResult.timedOut ? "Timed out" : cmdResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .err(code: "write_failed", message: msg.isEmpty ? "bd update failed" : msg)
        }

        // Refresh the bead after mutation
        let refreshResult = await GastownCommandRunner.bd(["show", beadID, "--json"])
        if refreshResult.succeeded, let detail = BeadModelParser.parseWritableDetail(from: refreshResult.stdout) {
            return .ok(beadDetailDict(detail))
        }

        return .ok(["bead_id": beadID, "updated": true])
    }

    // MARK: - beads.close

    /// Close a bead.
    ///
    /// Params:
    ///   - `bead_id` (String, required): The bead identifier.
    ///   - `reason` (String, optional): Close reason.
    ///
    /// Focus-intent: NO.
    static func beadsClose(params: [String: Any]) async -> Result {
        guard let beadID = trimmedString(params, "bead_id") else {
            return .err(code: "invalid_params", message: "Missing or empty 'bead_id' parameter")
        }

        var args = ["close", beadID]
        if let reason = trimmedString(params, "reason") {
            args.append(contentsOf: ["--reason", reason])
        }

        let cmdResult = await GastownCommandRunner.bd(args)
        guard cmdResult.succeeded else {
            let msg = cmdResult.timedOut ? "Timed out" : cmdResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .err(code: "write_failed", message: msg.isEmpty ? "bd close failed" : msg)
        }

        return .ok(["bead_id": beadID, "closed": true])
    }

    // MARK: - gastown.hooks.list

    /// List hook targets and their sync status.
    ///
    /// Focus-intent: NO.
    static func gastownHooksList(params: [String: Any]) async -> Result {
        let cmdResult = await GastownCommandRunner.gt(["hooks", "list", "--json"])
        guard cmdResult.succeeded else {
            let msg = cmdResult.timedOut ? "Timed out" : cmdResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .err(code: "command_failed", message: msg.isEmpty ? "gt hooks list failed" : msg)
        }

        guard let data = cmdResult.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return .ok(["targets": [] as [Any]])
        }

        return .ok(["targets": json])
    }

    // MARK: - gastown.hooks.sync

    /// Sync hooks configuration.
    ///
    /// Params:
    ///   - `target` (String, optional): Specific target to sync.
    ///
    /// Focus-intent: NO.
    static func gastownHooksSync(params: [String: Any]) async -> Result {
        var args = ["hooks", "sync"]
        if let target = trimmedString(params, "target") {
            args.append(target)
        }

        let cmdResult = await GastownCommandRunner.gt(args)
        guard cmdResult.succeeded else {
            let msg = cmdResult.timedOut ? "Timed out" : cmdResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .err(code: "sync_failed", message: msg.isEmpty ? "gt hooks sync failed" : msg)
        }

        return .ok(["synced": true, "output": cmdResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)])
    }

    // MARK: - gastown.convoy.list

    /// List active convoys.
    ///
    /// Focus-intent: NO.
    static func gastownConvoyList(params: [String: Any]) async -> Result {
        let cmdResult = await GastownCommandRunner.gt(["convoy", "list", "--json"])
        guard cmdResult.succeeded else {
            let msg = cmdResult.timedOut ? "Timed out" : cmdResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .err(code: "command_failed", message: msg.isEmpty ? "gt convoy list failed" : msg)
        }

        guard let data = cmdResult.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return .ok(["convoys": [] as [Any]])
        }

        return .ok(["convoys": json])
    }

    // MARK: - gastown.convoy.show

    /// Show convoy detail with tracked issues.
    ///
    /// Params:
    ///   - `convoy_id` (String, required): The convoy identifier.
    ///
    /// Focus-intent: NO.
    static func gastownConvoyShow(params: [String: Any]) async -> Result {
        guard let convoyID = trimmedString(params, "convoy_id") else {
            return .err(code: "invalid_params", message: "Missing or empty 'convoy_id' parameter")
        }

        let cmdResult = await GastownCommandRunner.gt(["convoy", "status", convoyID, "--json"])
        guard cmdResult.succeeded else {
            let msg = cmdResult.timedOut ? "Timed out" : cmdResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .err(code: "convoy_not_found", message: msg.isEmpty ? "Convoy '\(convoyID)' not found" : msg)
        }

        guard let detail = ConvoyModelParser.parseDetail(from: cmdResult.stdout) else {
            return .err(code: "parse_error", message: "Failed to parse convoy '\(convoyID)'")
        }

        return .ok(convoyDetailDict(detail))
    }

    // MARK: - gastown.convoy.add

    /// Add tracked work to a convoy.
    ///
    /// Params:
    ///   - `convoy_id` (String, required): The convoy identifier.
    ///   - `issue_ids` ([String], required): Issue IDs to add.
    ///
    /// Focus-intent: NO.
    static func gastownConvoyAdd(params: [String: Any]) async -> Result {
        guard let convoyID = trimmedString(params, "convoy_id") else {
            return .err(code: "invalid_params", message: "Missing or empty 'convoy_id' parameter")
        }

        let issueIDs: [String]
        if let arr = params["issue_ids"] as? [String] {
            issueIDs = arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        } else if let single = trimmedString(params, "issue_ids") {
            issueIDs = [single]
        } else {
            return .err(code: "invalid_params", message: "Missing or empty 'issue_ids' parameter")
        }

        var args = ["convoy", "add", convoyID]
        args.append(contentsOf: issueIDs)

        let cmdResult = await GastownCommandRunner.gt(args)
        guard cmdResult.succeeded else {
            let msg = cmdResult.timedOut ? "Timed out" : cmdResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .err(code: "write_failed", message: msg.isEmpty ? "gt convoy add failed" : msg)
        }

        return .ok(["convoy_id": convoyID, "added_issues": issueIDs])
    }

    // MARK: - gastown.peek

    /// Health-check a Gas Town agent.
    ///
    /// Params:
    ///   - `agent` (String, required): Agent name or address to peek.
    ///
    /// Focus-intent: NO.
    static func gastownPeek(params: [String: Any]) async -> Result {
        guard let agent = trimmedString(params, "agent") else {
            return .err(code: "invalid_params", message: "Missing or empty 'agent' parameter")
        }

        let cmdResult = await GastownCommandRunner.gt(["peek", agent, "--json"])
        guard cmdResult.succeeded else {
            let msg = cmdResult.timedOut ? "Timed out" : cmdResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .err(code: "command_failed", message: msg.isEmpty ? "gt peek failed" : msg)
        }

        guard let data = cmdResult.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .ok(["agent": agent, "raw": cmdResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)])
        }

        return .ok(json)
    }

    // MARK: - gastown.vitals

    /// Unified health dashboard for Gas Town.
    ///
    /// Focus-intent: NO.
    static func gastownVitals(params: [String: Any]) async -> Result {
        let cmdResult = await GastownCommandRunner.gt(["vitals", "--json"])
        guard cmdResult.succeeded else {
            let msg = cmdResult.timedOut ? "Timed out" : cmdResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .err(code: "command_failed", message: msg.isEmpty ? "gt vitals failed" : msg)
        }

        guard let data = cmdResult.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .ok(["raw": cmdResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)])
        }

        return .ok(json)
    }

    // MARK: - Private Helpers

    private static func trimmedString(_ params: [String: Any], _ key: String) -> String? {
        guard let raw = params[key] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func beadDetailDict(_ detail: WritableBeadDetail) -> [String: Any] {
        var dict: [String: Any] = [
            "bead_id": detail.id,
            "title": detail.title,
            "status": detail.status.rawValue,
        ]
        dict["description"] = detail.description ?? NSNull()
        dict["acceptance_criteria"] = detail.acceptanceCriteria ?? NSNull()
        dict["priority"] = detail.priority ?? NSNull()
        dict["issue_type"] = detail.issueType?.rawValue ?? NSNull()
        dict["assignee"] = detail.assignee ?? NSNull()
        dict["owner"] = detail.owner ?? NSNull()
        dict["estimated_minutes"] = detail.estimatedMinutes ?? NSNull()
        dict["created_at"] = detail.createdAt ?? NSNull()
        dict["updated_at"] = detail.updatedAt ?? NSNull()
        dict["external_ref"] = detail.externalRef ?? NSNull()
        dict["notes"] = detail.notes ?? NSNull()
        dict["design"] = detail.design ?? NSNull()
        return dict
    }

    private static func convoyDetailDict(_ detail: ConvoyDetail) -> [String: Any] {
        var dict: [String: Any] = [
            "convoy_id": detail.id,
        ]
        dict["name"] = detail.name ?? NSNull()
        dict["status"] = detail.status ?? NSNull()
        dict["subscriber_count"] = detail.subscriberCount ?? NSNull()
        dict["created_at"] = detail.createdAt ?? NSNull()
        dict["updated_at"] = detail.updatedAt ?? NSNull()

        if let tracked = detail.trackedIssues {
            dict["tracked_issues"] = tracked.map { issue -> [String: Any] in
                var d: [String: Any] = ["id": issue.id]
                d["title"] = issue.title ?? NSNull()
                d["status"] = issue.status ?? NSNull()
                d["prefix"] = issue.prefix ?? NSNull()
                return d
            }
        } else {
            dict["tracked_issues"] = [] as [Any]
        }

        return dict
    }
}

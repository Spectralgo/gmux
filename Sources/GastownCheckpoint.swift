import Foundation

// MARK: - Checkpoint data model

/// Represents the data stored in a Gastown `.polecat-checkpoint.json` file.
/// These checkpoints are advisory context for semantic resume — they indicate
/// what a polecat was doing when its session ended, but do not guarantee that
/// the session can be restored exactly.
struct GastownCheckpoint: Codable, Sendable, Equatable {
    var molecule: String?
    var step: String?
    var hookedBead: String?
    var modifiedFiles: Int?
    var branch: String?
    var commit: String?
    var timestamp: TimeInterval?
    var polecatName: String?
    var rigName: String?

    enum CodingKeys: String, CodingKey {
        case molecule
        case step
        case hookedBead = "hooked_bead"
        case modifiedFiles = "modified_files"
        case branch
        case commit
        case timestamp
        case polecatName = "polecat_name"
        case rigName = "rig_name"
    }
}

/// Aggregates a parsed checkpoint with the filesystem context it was found in.
struct GastownCheckpointContext: Sendable, Equatable {
    let checkpoint: GastownCheckpoint
    let worktreePath: String
    let polecatName: String
    let rigName: String
    let checkpointFileDate: Date?

    var isStale: Bool {
        guard let fileDate = checkpointFileDate else { return true }
        return Date().timeIntervalSince(fileDate) > 3600
    }

    var shortCommit: String? {
        guard let commit = checkpoint.commit, commit.count >= 7 else {
            return checkpoint.commit
        }
        return String(commit.prefix(7))
    }
}

// MARK: - Checkpoint reader

enum GastownCheckpointReader {
    static let checkpointFileName = ".polecat-checkpoint.json"

    /// Scans the Gastown town root for polecat checkpoint files across all rigs.
    /// Returns checkpoint contexts for each valid checkpoint found.
    static func scanForCheckpoints(townRoot: String? = nil) -> [GastownCheckpointContext] {
        let root = townRoot ?? detectTownRoot()
        guard let root else { return [] }
        let fm = FileManager.default

        var results: [GastownCheckpointContext] = []
        let rootURL = URL(fileURLWithPath: root, isDirectory: true)

        guard let rigEntries = try? fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        for rigDir in rigEntries {
            guard (try? rigDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                continue
            }
            let rigName = rigDir.lastPathComponent
            let polecatsDir = rigDir.appendingPathComponent("polecats", isDirectory: true)
            guard fm.fileExists(atPath: polecatsDir.path) else { continue }

            guard let polecatEntries = try? fm.contentsOfDirectory(
                at: polecatsDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for polecatDir in polecatEntries {
                guard (try? polecatDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                    continue
                }
                let polecatName = polecatDir.lastPathComponent
                let worktreeDir = polecatDir.appendingPathComponent(rigName, isDirectory: true)

                // Check for checkpoint in the polecat root or in the rig worktree
                let candidatePaths = [
                    polecatDir.appendingPathComponent(checkpointFileName),
                    worktreeDir.appendingPathComponent(checkpointFileName),
                ]

                for candidateURL in candidatePaths {
                    guard let context = readCheckpoint(
                        at: candidateURL,
                        worktreePath: worktreeDir.path,
                        polecatName: polecatName,
                        rigName: rigName
                    ) else {
                        continue
                    }
                    results.append(context)
                    break // Only take the first valid checkpoint per polecat
                }
            }
        }

        return results.sorted { lhs, rhs in
            (lhs.checkpoint.timestamp ?? 0) > (rhs.checkpoint.timestamp ?? 0)
        }
    }

    /// Reads a single checkpoint file and wraps it in context.
    static func readCheckpoint(
        at fileURL: URL,
        worktreePath: String,
        polecatName: String,
        rigName: String
    ) -> GastownCheckpointContext? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }

        let decoder = JSONDecoder()
        guard var checkpoint = try? decoder.decode(GastownCheckpoint.self, from: data) else {
            return nil
        }

        // Fill in polecat/rig name from filesystem context if not in the JSON
        if checkpoint.polecatName == nil {
            checkpoint.polecatName = polecatName
        }
        if checkpoint.rigName == nil {
            checkpoint.rigName = rigName
        }

        let fileDate: Date? = {
            guard let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
                  let modDate = attrs[.modificationDate] as? Date else {
                return nil
            }
            return modDate
        }()

        return GastownCheckpointContext(
            checkpoint: checkpoint,
            worktreePath: worktreePath,
            polecatName: polecatName,
            rigName: rigName,
            checkpointFileDate: fileDate
        )
    }

    /// Attempts to detect the Gastown town root.
    /// Checks the GT_TOWN_ROOT environment variable, then common paths.
    private static func detectTownRoot() -> String? {
        let env = ProcessInfo.processInfo.environment
        if let townRoot = env["GT_TOWN_ROOT"], !townRoot.isEmpty {
            let url = URL(fileURLWithPath: townRoot, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) {
                return townRoot
            }
        }

        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(homeDir)/gt",
            "\(homeDir)/code/spectralGasTown",
        ]
        for candidate in candidates {
            let fm = FileManager.default
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: candidate, isDirectory: &isDir), isDir.boolValue {
                return candidate
            }
        }
        return nil
    }
}

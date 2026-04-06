import Foundation

// MARK: - Town Root Detection & Prerequisite Validation
//
// Detection search order:
//   1. GT_TOWN_ROOT environment variable (authoritative when set by gt CLI)
//   2. GT_ROOT environment variable (legacy alias)
//   3. Walk up from the current working directory looking for .beads/routes.jsonl
//   4. Check ~/code/spectralGasTown (common developer layout) — not hardcoded;
//      the walk-up strategy covers any layout.
//
// Town root marker: a directory containing .beads/routes.jsonl
// Rig marker: a subdirectory containing config.json with "type": "rig"

// MARK: - Data Types

/// Identifies a validated Gas Town root on disk.
struct TownRoot: Equatable, Sendable {
    /// Absolute path to the Town root directory.
    let path: String

    /// Absolute path to the `.beads/routes.jsonl` file.
    var routesPath: String { (path as NSString).appendingPathComponent(".beads/routes.jsonl") }

    /// Absolute path to the `.beads` directory.
    var beadsPath: String { (path as NSString).appendingPathComponent(".beads") }
}

/// Minimal rig metadata read from `<rig>/config.json`.
struct RigInfo: Equatable, Sendable, Identifiable {
    let name: String
    /// Absolute path to the rig directory (e.g. `<town>/gmux`).
    let path: String
    let gitURL: String?
    let defaultBranch: String?
    let beadsPrefix: String?

    var id: String { name }
}

/// A prerequisite that Town detection can validate.
enum TownPrerequisite: String, CaseIterable, Sendable {
    case townRootExists = "town-root-exists"
    case beadsDirectoryExists = "beads-directory-exists"
    case routesFileExists = "routes-file-exists"
    case atLeastOneRig = "at-least-one-rig"
    case gtCLIAvailable = "gt-cli-available"
}

/// Result of checking a single prerequisite.
struct PrerequisiteResult: Equatable, Sendable {
    let prerequisite: TownPrerequisite
    let passed: Bool
    /// Human-readable guidance when the prerequisite fails.
    let guidance: String?
}

/// Structured error describing why Town detection failed.
enum TownDetectionError: Error, Equatable, Sendable {
    /// No Town root could be located through any detection strategy.
    case noTownRoot(searchedPaths: [String])
    /// A candidate Town root was found but is missing required structure.
    case invalidTownLayout(path: String, failures: [PrerequisiteResult])
    /// The `gt` CLI is not installed or not on PATH.
    case gtCLINotFound
}

/// Successful detection result with the validated Town and its rigs.
struct TownDiscoveryResult: Equatable, Sendable {
    let town: TownRoot
    let rigs: [RigInfo]
    let prerequisites: [PrerequisiteResult]
    let gtCLIPath: String?
}

// MARK: - Discovery Service

/// Locates a Gas Town root, validates prerequisites, and enumerates rigs.
///
/// Designed as a stateless value-oriented service so later inventory and identity
/// tasks can reuse it without coupling to any particular view or lifecycle.
struct GasTownDiscovery {

    // MARK: - Configuration

    /// Abstraction over environment and filesystem access for testability.
    struct Environment: Sendable {
        var getenv: @Sendable (String) -> String?
        var fileExists: @Sendable (String) -> Bool
        var isDirectory: @Sendable (String) -> Bool
        var contentsOfDirectory: @Sendable (String) -> [String]
        var contentsOfFile: @Sendable (String) -> Data?
        var currentDirectoryPath: @Sendable () -> String
        var homeDirectoryPath: @Sendable () -> String
        var whichGT: @Sendable () -> String?

        static let live = Environment(
            getenv: { key in
                ProcessInfo.processInfo.environment[key]
            },
            fileExists: { path in
                FileManager.default.fileExists(atPath: path)
            },
            isDirectory: { path in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
            },
            contentsOfDirectory: { path in
                (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
            },
            contentsOfFile: { path in
                FileManager.default.contents(atPath: path)
            },
            currentDirectoryPath: {
                FileManager.default.currentDirectoryPath
            },
            homeDirectoryPath: {
                FileManager.default.homeDirectoryForCurrentUser.path
            },
            whichGT: {
                GasTownDiscovery.resolveGTCLI()
            }
        )
    }

    let environment: Environment

    init(environment: Environment = .live) {
        self.environment = environment
    }

    // MARK: - Public API

    /// Attempt to discover a valid Town root and return a full result.
    ///
    /// Returns `.success` with the discovery result when a valid Town is found,
    /// or `.failure` with a structured error describing what went wrong.
    func discover() -> Result<TownDiscoveryResult, TownDetectionError> {
        let gtPath = environment.whichGT()

        // Phase 1: Locate a candidate Town root path.
        let candidate = locateTownRoot()

        guard let candidatePath = candidate else {
            let searched = searchedPaths()
            // If gt CLI is also missing, surface that as a more fundamental error.
            if gtPath == nil {
                return .failure(.gtCLINotFound)
            }
            return .failure(.noTownRoot(searchedPaths: searched))
        }

        // Phase 2: Validate the candidate.
        var prereqs: [PrerequisiteResult] = []

        prereqs.append(checkPrerequisite(.townRootExists, at: candidatePath))
        prereqs.append(checkPrerequisite(.beadsDirectoryExists, at: candidatePath))
        prereqs.append(checkPrerequisite(.routesFileExists, at: candidatePath))

        let rigs = enumerateRigs(at: candidatePath)
        let hasRig = !rigs.isEmpty
        prereqs.append(PrerequisiteResult(
            prerequisite: .atLeastOneRig,
            passed: hasRig,
            guidance: hasRig ? nil : String(
                localized: "town.prerequisite.noRigs",
                defaultValue: "No rigs found in \(candidatePath). Create a rig with 'gt rig create <name>'."
            )
        ))

        prereqs.append(PrerequisiteResult(
            prerequisite: .gtCLIAvailable,
            passed: gtPath != nil,
            guidance: gtPath != nil ? nil : String(
                localized: "town.prerequisite.gtMissing",
                defaultValue: "The 'gt' command-line tool is not installed or not on your PATH. Install Gas Town to use Gastown features."
            )
        ))

        let failures = prereqs.filter { !$0.passed }
        // Town root must exist and have a .beads directory at minimum.
        let criticalFailures = failures.filter {
            $0.prerequisite == .townRootExists || $0.prerequisite == .beadsDirectoryExists
        }
        if !criticalFailures.isEmpty {
            return .failure(.invalidTownLayout(path: candidatePath, failures: failures))
        }

        let town = TownRoot(path: candidatePath)
        return .success(TownDiscoveryResult(
            town: town,
            rigs: rigs,
            prerequisites: prereqs,
            gtCLIPath: gtPath
        ))
    }

    // MARK: - Detection Strategies

    /// Search order for locating the Town root.
    private func locateTownRoot() -> String? {
        // Strategy 1: GT_TOWN_ROOT env var (authoritative).
        if let envRoot = environment.getenv("GT_TOWN_ROOT"),
           !envRoot.isEmpty,
           isTownRoot(envRoot) {
            return envRoot
        }

        // Strategy 2: GT_ROOT env var (legacy alias).
        if let envRoot = environment.getenv("GT_ROOT"),
           !envRoot.isEmpty,
           isTownRoot(envRoot) {
            return envRoot
        }

        // Strategy 3: Walk up from cwd looking for .beads/routes.jsonl.
        let cwd = environment.currentDirectoryPath()
        if let found = walkUpForTownRoot(from: cwd) {
            return found
        }

        // Strategy 4: Check ~/gt/ (common convention).
        let home = environment.homeDirectoryPath()
        let defaultPath = (home as NSString).appendingPathComponent("gt")
        if isTownRoot(defaultPath) {
            return defaultPath
        }

        return nil
    }

    /// Returns the list of paths that were searched (for error reporting).
    private func searchedPaths() -> [String] {
        var paths: [String] = []
        if let envRoot = environment.getenv("GT_TOWN_ROOT"), !envRoot.isEmpty {
            paths.append(envRoot)
        }
        if let envRoot = environment.getenv("GT_ROOT"), !envRoot.isEmpty, !paths.contains(envRoot) {
            paths.append(envRoot)
        }
        let cwd = environment.currentDirectoryPath()
        paths.append(cwd)
        let home = environment.homeDirectoryPath()
        let defaultPath = (home as NSString).appendingPathComponent("gt")
        if !paths.contains(defaultPath) {
            paths.append(defaultPath)
        }
        return paths
    }

    /// Check whether a directory looks like a Town root.
    private func isTownRoot(_ path: String) -> Bool {
        guard environment.isDirectory(path) else { return false }
        let routesPath = (path as NSString).appendingPathComponent(".beads/routes.jsonl")
        return environment.fileExists(routesPath)
    }

    /// Walk up directory parents from `start` looking for a Town root marker.
    private func walkUpForTownRoot(from start: String) -> String? {
        var current = start
        let root = "/"
        while current != root && !current.isEmpty {
            if isTownRoot(current) {
                return current
            }
            current = (current as NSString).deletingLastPathComponent
        }
        // Check / itself (unlikely but complete).
        if isTownRoot(root) {
            return root
        }
        return nil
    }

    // MARK: - Prerequisite Checks

    private func checkPrerequisite(_ prereq: TownPrerequisite, at townPath: String) -> PrerequisiteResult {
        switch prereq {
        case .townRootExists:
            let exists = environment.isDirectory(townPath)
            return PrerequisiteResult(
                prerequisite: prereq,
                passed: exists,
                guidance: exists ? nil : String(
                    localized: "town.prerequisite.rootMissing",
                    defaultValue: "Town root directory '\(townPath)' does not exist or is not a directory."
                )
            )

        case .beadsDirectoryExists:
            let beadsPath = (townPath as NSString).appendingPathComponent(".beads")
            let exists = environment.isDirectory(beadsPath)
            return PrerequisiteResult(
                prerequisite: prereq,
                passed: exists,
                guidance: exists ? nil : String(
                    localized: "town.prerequisite.beadsMissing",
                    defaultValue: "Expected '.beads' directory not found at '\(townPath)'. This directory may not be a Gas Town root."
                )
            )

        case .routesFileExists:
            let routesPath = (townPath as NSString).appendingPathComponent(".beads/routes.jsonl")
            let exists = environment.fileExists(routesPath)
            return PrerequisiteResult(
                prerequisite: prereq,
                passed: exists,
                guidance: exists ? nil : String(
                    localized: "town.prerequisite.routesMissing",
                    defaultValue: "Bead routing file 'routes.jsonl' not found in '.beads/'. Run 'gt init' to initialize the Town."
                )
            )

        case .atLeastOneRig, .gtCLIAvailable:
            // These are handled inline in discover() where we have the needed context.
            return PrerequisiteResult(prerequisite: prereq, passed: true, guidance: nil)
        }
    }

    // MARK: - Rig Enumeration

    /// Scan immediate subdirectories of the Town root for rig config files.
    func enumerateRigs(at townPath: String) -> [RigInfo] {
        let entries = environment.contentsOfDirectory(townPath)
        var rigs: [RigInfo] = []

        for entry in entries {
            // Skip hidden directories and known non-rig entries.
            if entry.hasPrefix(".") { continue }

            let entryPath = (townPath as NSString).appendingPathComponent(entry)
            guard environment.isDirectory(entryPath) else { continue }

            let configPath = (entryPath as NSString).appendingPathComponent("config.json")
            guard let data = environment.contentsOfFile(configPath) else { continue }

            if let rigInfo = parseRigConfig(data: data, dirName: entry, dirPath: entryPath) {
                rigs.append(rigInfo)
            }
        }

        return rigs.sorted { $0.name < $1.name }
    }

    /// Parse a rig's config.json into a RigInfo.
    private func parseRigConfig(data: Data, dirName: String, dirPath: String) -> RigInfo? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              type == "rig" else {
            return nil
        }

        let name = (json["name"] as? String) ?? dirName
        let gitURL = json["git_url"] as? String
        let defaultBranch = json["default_branch"] as? String
        let beadsPrefix: String?
        if let beads = json["beads"] as? [String: Any] {
            beadsPrefix = beads["prefix"] as? String
        } else {
            beadsPrefix = nil
        }

        return RigInfo(
            name: name,
            path: dirPath,
            gitURL: gitURL,
            defaultBranch: defaultBranch,
            beadsPrefix: beadsPrefix
        )
    }

    // MARK: - gt CLI Resolution

    /// Attempt to find the `gt` binary on PATH.
    static func resolveGTCLI() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["gt"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let path, !path.isEmpty {
                    return path
                }
            }
        } catch {
            // which not available or failed — gt not on PATH.
        }
        return nil
    }
}

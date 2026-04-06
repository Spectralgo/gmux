import Foundation

/// Discovers rigs within a Gas Town root and produces an immutable inventory snapshot.
///
/// This adapter reads `rigs.json` from the Town root, then walks each rig directory
/// to collect config, role directories, and health indicators. One broken rig does
/// not prevent the rest from being discovered — failures are captured alongside
/// healthy rigs in the returned snapshot.
///
/// Thread-safety: the adapter holds no mutable state; each call to `discover`
/// produces an independent snapshot.
enum RigInventoryAdapter {

    // MARK: - Public

    /// Discover all rigs registered in the given Town.
    ///
    /// - Parameter town: A validated Gas Town root directory.
    /// - Returns: A snapshot containing discovered rigs and any failures.
    static func discover(town: GasTownRoot) -> RigInventorySnapshot {
        let rigsJsonURL = town.path.appendingPathComponent("rigs.json")

        guard let data = try? Data(contentsOf: rigsJsonURL) else {
            return RigInventorySnapshot(
                town: town,
                rigs: [],
                failures: [
                    RigDiscoveryFailure(
                        rigName: "(manifest)",
                        rigPath: rigsJsonURL,
                        reason: "Could not read rigs.json at \(rigsJsonURL.path)"
                    )
                ],
                timestamp: Date()
            )
        }

        guard let manifest = try? JSONDecoder().decode(RigsManifest.self, from: data) else {
            return RigInventorySnapshot(
                town: town,
                rigs: [],
                failures: [
                    RigDiscoveryFailure(
                        rigName: "(manifest)",
                        rigPath: rigsJsonURL,
                        reason: "rigs.json exists but could not be decoded"
                    )
                ],
                timestamp: Date()
            )
        }

        var rigs: [Rig] = []
        var failures: [RigDiscoveryFailure] = []

        for (name, _) in manifest.rigs.sorted(by: { $0.key < $1.key }) {
            let rigPath = town.path.appendingPathComponent(name)

            guard FileManager.default.fileExists(atPath: rigPath.path) else {
                failures.append(RigDiscoveryFailure(
                    rigName: name,
                    rigPath: rigPath,
                    reason: "Rig directory does not exist"
                ))
                continue
            }

            let result = discoverRig(name: name, rigPath: rigPath)
            switch result {
            case .success(let rig):
                rigs.append(rig)
            case .failure(let failure):
                failures.append(failure)
            }
        }

        return RigInventorySnapshot(
            town: town,
            rigs: rigs,
            failures: failures,
            timestamp: Date()
        )
    }

    // MARK: - Private

    private static func discoverRig(
        name: String,
        rigPath: URL
    ) -> Result<Rig, RigDiscoveryFailure> {
        var issues: [HealthIssue] = []

        // --- config.json ---
        let configURL = rigPath.appendingPathComponent("config.json")
        let config: RigConfig

        if let data = try? Data(contentsOf: configURL),
           let decoded = try? JSONDecoder().decode(RigConfig.self, from: data) {
            config = decoded
        } else if FileManager.default.fileExists(atPath: configURL.path) {
            issues.append(HealthIssue(
                severity: .error,
                category: .invalidConfig,
                message: "config.json exists but could not be decoded"
            ))
            // Cannot proceed without a valid config.
            return .failure(RigDiscoveryFailure(
                rigName: name,
                rigPath: rigPath,
                reason: "config.json could not be decoded"
            ))
        } else {
            issues.append(HealthIssue(
                severity: .error,
                category: .missingConfig,
                message: "config.json not found"
            ))
            return .failure(RigDiscoveryFailure(
                rigName: name,
                rigPath: rigPath,
                reason: "config.json not found"
            ))
        }

        // --- .beads/ ---
        let beadsPath = rigPath.appendingPathComponent(".beads")
        if !FileManager.default.fileExists(atPath: beadsPath.path) {
            issues.append(HealthIssue(
                severity: .warning,
                category: .missingBeads,
                message: ".beads/ directory not found"
            ))
        }

        // --- Role directories ---
        var roles: [RigRole: RoleDirectory] = [:]
        for role in RigRole.allCases {
            let roleDir = discoverRole(role: role, rigPath: rigPath, issues: &issues)
            roles[role] = roleDir
        }

        let rig = Rig(
            id: name,
            name: name,
            path: rigPath,
            config: config,
            roles: roles,
            health: RigHealth(issues: issues)
        )
        return .success(rig)
    }

    private static func discoverRole(
        role: RigRole,
        rigPath: URL,
        issues: inout [HealthIssue]
    ) -> RoleDirectory {
        let rolePath = rigPath.appendingPathComponent(role.rawValue)
        let fm = FileManager.default

        guard fm.fileExists(atPath: rolePath.path) else {
            issues.append(HealthIssue(
                severity: .warning,
                category: .missingRoleDirectory,
                message: "\(role.rawValue)/ directory not found"
            ))
            return RoleDirectory(role: role, path: rolePath, status: .missing, members: [])
        }

        if role.isSingular {
            // Singular roles have a workspace at <role>/rig/
            let rigSubdir = rolePath.appendingPathComponent("rig")
            let status: RoleStatus = fm.fileExists(atPath: rigSubdir.path) ? .present : .empty
            return RoleDirectory(role: role, path: rolePath, status: status, members: [])
        }

        // Multi-member roles: list subdirectories as member names.
        let members = listSubdirectories(at: rolePath)
        let status: RoleStatus = members.isEmpty ? .empty : .present
        return RoleDirectory(role: role, path: rolePath, status: status, members: members)
    }

    /// Returns sorted subdirectory names at the given URL, excluding hidden directories.
    private static func listSubdirectories(at url: URL) -> [String] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            .sorted()
    }
}

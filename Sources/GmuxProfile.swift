import Foundation

// MARK: - Profile Model

/// A named isolation boundary for Town roots, sockets, caches, and actor state.
///
/// Each profile scopes all runtime artifacts to its own subdirectory tree so that
/// multiple Town environments (e.g. separate Towns or agent integrations) never
/// silently share state. The ``default`` profile preserves the pre-profile layout
/// used by M0's gmux-scoped identity so existing single-Town installs are unaffected.
struct GmuxProfile: Codable, Identifiable, Hashable, Sendable {
    /// A stable, filesystem-safe identifier. Must match `[A-Za-z0-9._-]+`.
    let id: String

    /// Human-readable label shown in UI and logs.
    var displayName: String

    /// Absolute path to the Town root this profile targets.
    /// `nil` means "use auto-detection at runtime" (the default single-Town behavior).
    var townRootPath: String?

    /// Optional override for the Beads actor identity (`BD_ACTOR`).
    var actorIdentity: String?

    /// Optional override for the Gas Town role context (`GT_ROLE`).
    var roleContext: String?

    /// When this profile was created (epoch seconds).
    var createdAt: TimeInterval

    // MARK: Well-Known Profiles

    /// The default profile preserves M0's flat `gmux/` layout with no per-profile
    /// subdirectory, ensuring zero-migration for existing single-Town users.
    static let `default` = GmuxProfile(
        id: "default",
        displayName: String(localized: "profile.default.displayName", defaultValue: "Default"),
        townRootPath: nil,
        actorIdentity: nil,
        roleContext: nil,
        createdAt: 0
    )

    /// Whether this is the well-known default profile (flat layout, no subdirectory).
    var isDefault: Bool { id == Self.default.id }

    // MARK: Validation

    private static let validIDPattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9._-]+$")

    static func isValidID(_ candidate: String) -> Bool {
        guard !candidate.isEmpty else { return false }
        let range = NSRange(candidate.startIndex..., in: candidate)
        return validIDPattern.firstMatch(in: candidate, range: range) != nil
    }
}

// MARK: - Profile Path Resolver

/// Resolves per-profile paths for sockets, Application Support, caches, and
/// environment variables.
///
/// **Isolation rule:** The default profile uses the existing flat `gmux/` layout.
/// All other profiles scope into `gmux/profiles/<profile-id>/` to prevent
/// cross-contamination.
enum GmuxProfilePaths {
    private static let appSupportDirectoryName = "gmux"
    private static let profilesSubdirectory = "profiles"
    private static let socketFileName = "gmux.sock"
    private static let lastSocketPathFileName = "last-socket-path"
    private static let sessionSnapshotPrefix = "session-"

    // MARK: Application Support

    /// Application Support root for a profile.
    ///
    /// - default → `~/Library/Application Support/gmux/`
    /// - named   → `~/Library/Application Support/gmux/profiles/<id>/`
    static func appSupportDirectory(
        for profile: GmuxProfile,
        base: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let base = base ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let gmuxRoot = base.appendingPathComponent(appSupportDirectoryName, isDirectory: true)
        if profile.isDefault {
            return gmuxRoot
        }
        return gmuxRoot
            .appendingPathComponent(profilesSubdirectory, isDirectory: true)
            .appendingPathComponent(profile.id, isDirectory: true)
    }

    // MARK: Socket Paths

    /// Stable socket path for a profile.
    ///
    /// - default → `~/Library/Application Support/gmux/gmux.sock` (existing M0 path)
    /// - named   → `~/Library/Application Support/gmux/profiles/<id>/gmux.sock`
    static func socketPath(for profile: GmuxProfile, base: URL? = nil) -> String? {
        appSupportDirectory(for: profile, base: base)?
            .appendingPathComponent(socketFileName, isDirectory: false)
            .path
    }

    /// Last-socket-path marker for a profile.
    static func lastSocketPathFile(for profile: GmuxProfile, base: URL? = nil) -> String? {
        appSupportDirectory(for: profile, base: base)?
            .appendingPathComponent(lastSocketPathFileName, isDirectory: false)
            .path
    }

    // MARK: Session Persistence

    /// Session snapshot file URL for a profile.
    ///
    /// - default → `~/Library/Application Support/gmux/session-<bundleId>.json`
    ///   (existing M0 path for backwards compatibility)
    /// - named   → `~/Library/Application Support/gmux/profiles/<id>/session-<bundleId>.json`
    static func sessionSnapshotFileURL(
        for profile: GmuxProfile,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        base: URL? = nil
    ) -> URL? {
        guard let directory = appSupportDirectory(for: profile, base: base) else { return nil }
        let bundleId = bundleIdentifier.flatMap { id in
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } ?? "com.gmuxterm.app"
        let safeBundleId = bundleId.replacingOccurrences(
            of: "[^A-Za-z0-9._-]",
            with: "_",
            options: .regularExpression
        )
        return directory.appendingPathComponent(
            "\(sessionSnapshotPrefix)\(safeBundleId).json",
            isDirectory: false
        )
    }

    // MARK: Cache Directory

    /// Cache root for a profile.
    ///
    /// - default → `~/Library/Caches/gmux/`
    /// - named   → `~/Library/Caches/gmux/profiles/<id>/`
    static func cacheDirectory(
        for profile: GmuxProfile,
        base: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let base = base ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let gmuxRoot = base.appendingPathComponent(appSupportDirectoryName, isDirectory: true)
        if profile.isDefault {
            return gmuxRoot
        }
        return gmuxRoot
            .appendingPathComponent(profilesSubdirectory, isDirectory: true)
            .appendingPathComponent(profile.id, isDirectory: true)
    }

    // MARK: Socket Password

    /// Socket password file for a profile.
    static func socketPasswordFileURL(for profile: GmuxProfile, base: URL? = nil) -> URL? {
        guard let directory = appSupportDirectory(for: profile, base: base) else { return nil }
        return directory
            .appendingPathComponent(SocketControlPasswordStore.directoryName, isDirectory: true)
            .appendingPathComponent(SocketControlPasswordStore.fileName, isDirectory: false)
    }

    // MARK: Environment Variables

    /// Environment variable overrides that should be injected into subprocesses
    /// launched under this profile.
    static func environmentOverrides(for profile: GmuxProfile) -> [String: String] {
        var env: [String: String] = [:]
        if let townRoot = profile.townRootPath {
            env["GMUX_TOWN_ROOT"] = townRoot
        }
        if let actor = profile.actorIdentity {
            env["BD_ACTOR"] = actor
        }
        if let role = profile.roleContext {
            env["GT_ROLE"] = role
        }
        if !profile.isDefault {
            env["GMUX_PROFILE"] = profile.id
        }
        return env
    }
}

// MARK: - Profile Store

/// Persistent storage and selection of profiles.
///
/// Profiles are stored in `~/Library/Application Support/gmux/profiles.json`.
/// The active profile ID is stored in UserDefaults under `gmuxActiveProfileID`.
/// The default profile is always implicitly available and does not need to be
/// stored in the profiles file.
enum GmuxProfileStore {
    static let activeProfileDefaultsKey = "gmuxActiveProfileID"
    static let didChangeNotification = Notification.Name("gmux.profileDidChange")
    private static let profilesFileName = "profiles.json"
    private static let appSupportDirectoryName = "gmux"

    // MARK: Active Profile

    /// Load the currently selected profile. Falls back to `.default` when the
    /// persisted ID is missing or no longer present in the profile list.
    static func activeProfile(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) -> GmuxProfile {
        // Check env var override first (deterministic for automation/agents).
        if let envProfile = ProcessInfo.processInfo.environment["GMUX_PROFILE"],
           !envProfile.isEmpty {
            if envProfile == GmuxProfile.default.id {
                return .default
            }
            if let profiles = loadProfiles(fileManager: fileManager),
               let match = profiles.first(where: { $0.id == envProfile }) {
                return match
            }
            // Unknown profile ID from env — fall through to defaults.
        }

        guard let storedID = defaults.string(forKey: activeProfileDefaultsKey),
              !storedID.isEmpty else {
            return .default
        }
        if storedID == GmuxProfile.default.id {
            return .default
        }
        guard let profiles = loadProfiles(fileManager: fileManager),
              let match = profiles.first(where: { $0.id == storedID }) else {
            return .default
        }
        return match
    }

    /// Set the active profile by ID. Posts ``didChangeNotification``.
    static func setActiveProfile(
        _ profileID: String,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(profileID, forKey: activeProfileDefaultsKey)
        NotificationCenter.default.post(name: didChangeNotification, object: profileID)
    }

    // MARK: Profile List

    /// All stored profiles (excludes the implicit default).
    static func loadProfiles(fileManager: FileManager = .default) -> [GmuxProfile]? {
        guard let fileURL = profilesFileURL(fileManager: fileManager) else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode([GmuxProfile].self, from: data)
    }

    /// All available profiles including the implicit default.
    static func allProfiles(fileManager: FileManager = .default) -> [GmuxProfile] {
        var result: [GmuxProfile] = [.default]
        if let stored = loadProfiles(fileManager: fileManager) {
            result.append(contentsOf: stored)
        }
        return result
    }

    /// Save the profile list (excludes the implicit default).
    @discardableResult
    static func saveProfiles(
        _ profiles: [GmuxProfile],
        fileManager: FileManager = .default
    ) -> Bool {
        guard let fileURL = profilesFileURL(fileManager: fileManager) else { return false }
        let directory = fileURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(profiles.filter { !$0.isDefault })
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Add a profile. Returns `false` if the ID is invalid or already exists.
    @discardableResult
    static func addProfile(
        _ profile: GmuxProfile,
        fileManager: FileManager = .default
    ) -> Bool {
        guard GmuxProfile.isValidID(profile.id), !profile.isDefault else { return false }
        var existing = loadProfiles(fileManager: fileManager) ?? []
        guard !existing.contains(where: { $0.id == profile.id }) else { return false }
        existing.append(profile)
        return saveProfiles(existing, fileManager: fileManager)
    }

    /// Remove a profile by ID. The default profile cannot be removed.
    @discardableResult
    static func removeProfile(
        _ profileID: String,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) -> Bool {
        guard profileID != GmuxProfile.default.id else { return false }
        var existing = loadProfiles(fileManager: fileManager) ?? []
        let countBefore = existing.count
        existing.removeAll { $0.id == profileID }
        guard existing.count < countBefore else { return false }
        let saved = saveProfiles(existing, fileManager: fileManager)
        if saved, defaults.string(forKey: activeProfileDefaultsKey) == profileID {
            setActiveProfile(GmuxProfile.default.id, defaults: defaults)
        }
        return saved
    }

    // MARK: Internal

    private static func profilesFileURL(fileManager: FileManager = .default) -> URL? {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport
            .appendingPathComponent(appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent(profilesFileName, isDirectory: false)
    }
}

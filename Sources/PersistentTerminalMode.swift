import Foundation

// MARK: - Persistent Terminal Mode

/// Defines the supported persistent-terminal integration modes.
///
/// cmux can restore UI/session metadata on relaunch, but live processes (SSH,
/// agents, long-running tasks) are not restored by the default metadata-only
/// mode. Persistent terminal modes cooperate with external mux backends to
/// offer stronger session survival guarantees, with clearly documented
/// tradeoffs per backend.
///
/// **Design principle:** Keep the adapter surface small and explicit. cmux does
/// not own or hide backend behavior — it cooperates with backends and surfaces
/// their limitations honestly.
enum PersistentTerminalMode: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Default. Restores workspace layout, CWDs, scrollback text, and browser
    /// URLs. Does **not** preserve live terminal processes.
    case metadataOnly

    /// Launches terminal sessions inside tmux. On restart, reattaches to the
    /// existing tmux server. Optionally cooperates with tmux-resurrect for
    /// layout + program restore across tmux server restarts.
    ///
    /// **What it preserves:** tmux sessions/windows/panes, CWDs, layouts.
    /// With tmux-resurrect: best-effort program restore via configurable
    /// strategies.
    ///
    /// **Limitations:** Requires tmux installed. Program restore is best-effort
    /// (not all programs can be re-launched). tmux-resurrect requires explicit
    /// save (prefix + Ctrl-s) or tmux-continuum for periodic auto-save.
    case tmuxResurrect

    /// Launches terminal sessions inside Zellij. On restart, reattaches to the
    /// existing Zellij session with built-in persistence.
    ///
    /// **What it preserves:** Zellij sessions with all panes and running
    /// processes (via detach/reattach).
    ///
    /// **Limitations:** Requires Zellij installed. Experimental integration —
    /// platform support and cmux-Zellij protocol may evolve. Zellij manages
    /// its own layout which may diverge from cmux workspace layout.
    case zellij

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .metadataOnly:
            return String(
                localized: "persistentTerminal.metadataOnly.name",
                defaultValue: "Metadata only"
            )
        case .tmuxResurrect:
            return String(
                localized: "persistentTerminal.tmuxResurrect.name",
                defaultValue: "tmux (with resurrect)"
            )
        case .zellij:
            return String(
                localized: "persistentTerminal.zellij.name",
                defaultValue: "Zellij"
            )
        }
    }

    var description: String {
        switch self {
        case .metadataOnly:
            return String(
                localized: "persistentTerminal.metadataOnly.description",
                defaultValue: "Restores layout, working directories, and scrollback. Live processes are not preserved."
            )
        case .tmuxResurrect:
            return String(
                localized: "persistentTerminal.tmuxResurrect.description",
                defaultValue: "Runs terminals inside tmux. Reattaches on restart. Program restore is best-effort via tmux-resurrect."
            )
        case .zellij:
            return String(
                localized: "persistentTerminal.zellij.description",
                defaultValue: "Runs terminals inside Zellij. Reattaches with built-in session persistence. Experimental."
            )
        }
    }

    /// User-facing explanation of what this mode **cannot** do, shown in
    /// settings UI to set correct expectations.
    var limitations: String {
        switch self {
        case .metadataOnly:
            return String(
                localized: "persistentTerminal.metadataOnly.limitations",
                defaultValue: "SSH connections, running commands, and background jobs are lost on quit."
            )
        case .tmuxResurrect:
            return String(
                localized: "persistentTerminal.tmuxResurrect.limitations",
                defaultValue: "Requires tmux. Not all programs can be restored — tmux-resurrect uses best-effort strategies. Automatic save requires tmux-continuum."
            )
        case .zellij:
            return String(
                localized: "persistentTerminal.zellij.limitations",
                defaultValue: "Requires Zellij. Experimental — Zellij manages its own layout which may not match cmux workspaces exactly."
            )
        }
    }

    /// Whether this mode requires an external binary to function.
    var requiresExternalBinary: Bool {
        switch self {
        case .metadataOnly:
            return false
        case .tmuxResurrect, .zellij:
            return true
        }
    }
}

// MARK: - Backend Status

/// Runtime detection result for a persistent terminal backend.
struct PersistentTerminalBackendStatus: Sendable, Equatable {
    let mode: PersistentTerminalMode
    let binaryFound: Bool
    let binaryPath: String?
    let version: String?
    let pluginAvailable: Bool

    /// Whether the backend is ready to use.
    var isAvailable: Bool {
        switch mode {
        case .metadataOnly:
            return true
        case .tmuxResurrect:
            return binaryFound
        case .zellij:
            return binaryFound
        }
    }

    /// User-facing status summary.
    var statusDescription: String {
        if isAvailable {
            if let version {
                return String(
                    localized: "persistentTerminal.status.available",
                    defaultValue: "Available (v\(version))"
                )
            }
            return String(
                localized: "persistentTerminal.status.availableNoVersion",
                defaultValue: "Available"
            )
        }
        return String(
            localized: "persistentTerminal.status.notFound",
            defaultValue: "Not installed"
        )
    }

    static func metadataOnly() -> PersistentTerminalBackendStatus {
        PersistentTerminalBackendStatus(
            mode: .metadataOnly,
            binaryFound: true,
            binaryPath: nil,
            version: nil,
            pluginAvailable: true
        )
    }
}

// MARK: - Backend Detection

enum PersistentTerminalBackendDetector {
    /// Probes the system for backend availability.
    static func detect(
        mode: PersistentTerminalMode,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> PersistentTerminalBackendStatus {
        switch mode {
        case .metadataOnly:
            return .metadataOnly()
        case .tmuxResurrect:
            return detectTmux(environment: environment)
        case .zellij:
            return detectZellij(environment: environment)
        }
    }

    /// Detect all backends in parallel and return results.
    static func detectAll(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [PersistentTerminalBackendStatus] {
        PersistentTerminalMode.allCases.map { detect(mode: $0, environment: environment) }
    }

    private static func detectTmux(
        environment: [String: String]
    ) -> PersistentTerminalBackendStatus {
        let (found, path) = findBinary("tmux", environment: environment)
        let version = found ? binaryVersion("tmux", arguments: ["-V"]) : nil
        let pluginAvailable = found && tmuxResurrectPluginAvailable(environment: environment)
        return PersistentTerminalBackendStatus(
            mode: .tmuxResurrect,
            binaryFound: found,
            binaryPath: path,
            version: version,
            pluginAvailable: pluginAvailable
        )
    }

    private static func detectZellij(
        environment: [String: String]
    ) -> PersistentTerminalBackendStatus {
        let (found, path) = findBinary("zellij", environment: environment)
        let version = found ? binaryVersion("zellij", arguments: ["--version"]) : nil
        return PersistentTerminalBackendStatus(
            mode: .zellij,
            binaryFound: found,
            binaryPath: path,
            version: version,
            pluginAvailable: true
        )
    }

    private static func findBinary(
        _ name: String,
        environment: [String: String]
    ) -> (found: Bool, path: String?) {
        let pathDirs = (environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin")
            .split(separator: ":")
            .map(String.init)

        for dir in pathDirs {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return (true, candidate)
            }
        }

        // Check common Homebrew and system paths not always in PATH.
        let fallbackPaths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
        ]
        for candidate in fallbackPaths {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return (true, candidate)
            }
        }

        return (false, nil)
    }

    private static func binaryVersion(
        _ binary: String,
        arguments: [String]
    ) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [binary] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // tmux outputs "tmux 3.4" — extract version part.
            // zellij outputs "zellij 0.40.1" — extract version part.
            let components = output.split(separator: " ", maxSplits: 1)
            return components.count > 1 ? String(components[1]) : (output.isEmpty ? nil : output)
        } catch {
            return nil
        }
    }

    private static func tmuxResurrectPluginAvailable(
        environment: [String: String]
    ) -> Bool {
        let home = environment["HOME"] ?? NSHomeDirectory()
        let pluginPaths = [
            (home as NSString).appendingPathComponent(".tmux/plugins/tmux-resurrect"),
            (home as NSString).appendingPathComponent(".config/tmux/plugins/tmux-resurrect"),
        ]
        return pluginPaths.contains { path in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
        }
    }
}

// MARK: - Adapter Protocol

/// Minimal adapter interface for persistent terminal backends.
///
/// Each adapter translates cmux workspace lifecycle events into
/// backend-specific operations. The adapter does not replace cmux's own session
/// persistence — it augments it by keeping live processes alive.
protocol PersistentTerminalAdapter: Sendable {
    /// The mode this adapter handles.
    var mode: PersistentTerminalMode { get }

    /// Shell command and environment to wrap a new terminal session so it runs
    /// inside the backend. Returns nil if the backend should not wrap this
    /// session (e.g., binary not found).
    ///
    /// - Parameters:
    ///   - sessionName: Unique session identifier (derived from workspace/panel ID).
    ///   - workingDirectory: Initial working directory for the session.
    /// - Returns: A launch configuration, or nil to fall back to a plain shell.
    func launchConfiguration(
        sessionName: String,
        workingDirectory: String
    ) -> PersistentTerminalLaunchConfig?

    /// Attempt to reattach to an existing backend session.
    ///
    /// - Parameter sessionName: The session identifier used at launch time.
    /// - Returns: A launch configuration for reattach, or nil if no session exists.
    func reattachConfiguration(
        sessionName: String
    ) -> PersistentTerminalLaunchConfig?
}

/// Launch configuration produced by an adapter.
struct PersistentTerminalLaunchConfig: Sendable, Equatable {
    /// The shell command to execute (e.g., "tmux new-session -s <name>").
    let command: String

    /// Additional environment variables to set for the terminal process.
    let environment: [String: String]
}

// MARK: - Adapter Implementations

/// Adapter for tmux with optional tmux-resurrect support.
struct TmuxResurrectAdapter: PersistentTerminalAdapter {
    let mode = PersistentTerminalMode.tmuxResurrect
    let tmuxPath: String

    func launchConfiguration(
        sessionName: String,
        workingDirectory: String
    ) -> PersistentTerminalLaunchConfig? {
        let sanitized = Self.sanitizeSessionName(sessionName)
        // "new-session -A" attaches to an existing session or creates a new one.
        let command = "\(tmuxPath) new-session -A -s \(Self.shellQuote(sanitized)) -c \(Self.shellQuote(workingDirectory))"
        return PersistentTerminalLaunchConfig(command: command, environment: [:])
    }

    func reattachConfiguration(
        sessionName: String
    ) -> PersistentTerminalLaunchConfig? {
        let sanitized = Self.sanitizeSessionName(sessionName)
        let command = "\(tmuxPath) attach-session -t \(Self.shellQuote(sanitized))"
        return PersistentTerminalLaunchConfig(command: command, environment: [:])
    }

    /// tmux session names cannot contain periods or colons.
    static func sanitizeSessionName(_ name: String) -> String {
        name.replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Adapter for Zellij session persistence.
struct ZellijAdapter: PersistentTerminalAdapter {
    let mode = PersistentTerminalMode.zellij
    let zellijPath: String

    func launchConfiguration(
        sessionName: String,
        workingDirectory: String
    ) -> PersistentTerminalLaunchConfig? {
        let sanitized = Self.sanitizeSessionName(sessionName)
        // "attach --create" attaches to an existing session or creates a new one.
        let command = "\(zellijPath) attach --create \(Self.shellQuote(sanitized))"
        return PersistentTerminalLaunchConfig(
            command: command,
            environment: ["ZELLIJ_SESSION_NAME": sanitized]
        )
    }

    func reattachConfiguration(
        sessionName: String
    ) -> PersistentTerminalLaunchConfig? {
        let sanitized = Self.sanitizeSessionName(sessionName)
        let command = "\(zellijPath) attach \(Self.shellQuote(sanitized))"
        return PersistentTerminalLaunchConfig(
            command: command,
            environment: ["ZELLIJ_SESSION_NAME": sanitized]
        )
    }

    /// Zellij session names should be filesystem-safe.
    static func sanitizeSessionName(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

// MARK: - Adapter Factory

enum PersistentTerminalAdapterFactory {
    /// Create an adapter for the given mode, if the backend is available.
    ///
    /// Returns nil for `metadataOnly` (no adapter needed) or if the required
    /// binary is not found.
    static func adapter(
        for mode: PersistentTerminalMode,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> (any PersistentTerminalAdapter)? {
        switch mode {
        case .metadataOnly:
            return nil
        case .tmuxResurrect:
            let status = PersistentTerminalBackendDetector.detect(
                mode: .tmuxResurrect,
                environment: environment
            )
            guard status.binaryFound, let path = status.binaryPath else { return nil }
            return TmuxResurrectAdapter(tmuxPath: path)
        case .zellij:
            let status = PersistentTerminalBackendDetector.detect(
                mode: .zellij,
                environment: environment
            )
            guard status.binaryFound, let path = status.binaryPath else { return nil }
            return ZellijAdapter(zellijPath: path)
        }
    }
}

// MARK: - Settings

enum PersistentTerminalModeSettings {
    static let modeKey = "persistentTerminalMode"
    static let defaultMode: PersistentTerminalMode = .metadataOnly

    static func currentMode(defaults: UserDefaults = .standard) -> PersistentTerminalMode {
        guard let raw = defaults.string(forKey: modeKey) else { return defaultMode }
        return PersistentTerminalMode(rawValue: raw) ?? defaultMode
    }

    static func setMode(
        _ mode: PersistentTerminalMode,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(mode.rawValue, forKey: modeKey)
    }

    /// Resolve the effective mode. If a non-metadata mode is selected but the
    /// backend binary is not found, fall back to metadata-only and return the
    /// fallback reason.
    static func effectiveMode(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> (mode: PersistentTerminalMode, fallbackReason: String?) {
        if let envOverride = environment["CMUX_PERSISTENT_TERMINAL_MODE"],
           let overrideMode = PersistentTerminalMode(rawValue: envOverride) {
            return validateMode(overrideMode, environment: environment)
        }

        let selected = currentMode(defaults: defaults)
        return validateMode(selected, environment: environment)
    }

    private static func validateMode(
        _ mode: PersistentTerminalMode,
        environment: [String: String]
    ) -> (mode: PersistentTerminalMode, fallbackReason: String?) {
        guard mode.requiresExternalBinary else {
            return (mode, nil)
        }

        let status = PersistentTerminalBackendDetector.detect(
            mode: mode,
            environment: environment
        )

        if status.isAvailable {
            return (mode, nil)
        }

        let binaryName: String
        switch mode {
        case .tmuxResurrect: binaryName = "tmux"
        case .zellij: binaryName = "zellij"
        case .metadataOnly: binaryName = ""
        }

        let reason = String(
            localized: "persistentTerminal.fallback.binaryNotFound",
            defaultValue: "\(binaryName) not found — falling back to metadata-only restore."
        )
        return (.metadataOnly, reason)
    }
}

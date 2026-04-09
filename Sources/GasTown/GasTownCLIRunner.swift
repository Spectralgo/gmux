import Foundation

// MARK: - Gas Town CLI Runner
//
// Shared synchronous process runner and CLI resolution used by
// adapters that need blocking CLI execution (AgentHealthAdapter,
// ConvoyAdapter, HooksAdapter) and async runners (GastownCommandRunner,
// BeadsAdapter).
//
// GUI apps on macOS inherit a minimal PATH (/usr/bin:/bin:/usr/sbin:/sbin)
// that does not include Homebrew or user-local bin directories. This
// module provides:
//   - resolveExecutable(_:)  — finds gt/bd/etc. across common install paths
//   - cliEnvironment()       — builds an augmented environment with PATH,
//                               GT_TOWN_ROOT, and BEADS_DIR set correctly
//   - runProcess(...)        — launches a subprocess with the augmented env

enum GasTownCLIRunner {

    /// Result of a synchronous CLI invocation.
    struct CLIResult: Equatable, Sendable {
        let exitCode: Int32
        let stdout: Data
        let stderr: Data
    }

    // MARK: - Executable Resolution

    /// Directories to search when resolving CLI tool paths.
    /// Ordered by likelihood — Homebrew ARM, Homebrew Intel, user-local, system.
    static let cliSearchPaths: [String] = {
        var paths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            paths.append("\(home)/.local/bin")
            paths.append("\(home)/go/bin")
        }
        paths.append(contentsOf: ["/usr/bin", "/bin", "/usr/sbin", "/sbin"])
        return paths
    }()

    /// Resolve a CLI executable by name, searching common install directories.
    ///
    /// Returns the absolute path to the executable, or nil if not found.
    static func resolveExecutable(_ name: String) -> String? {
        let fm = FileManager.default
        for dir in cliSearchPaths {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Environment

    /// Build an augmented process environment suitable for running gt/bd.
    ///
    /// Starts from the current process environment, then:
    /// 1. Ensures PATH includes all `cliSearchPaths` directories.
    /// 2. Sets GT_TOWN_ROOT if a town root is known (from GasTownService or discovery).
    /// 3. Sets BEADS_DIR to the town's .beads directory.
    static func cliEnvironment(townRootPath: String? = nil) -> [String: String] {
        var env = ProcessInfo.processInfo.environment

        // Augment PATH with CLI search directories.
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let currentDirs = Set(currentPath.split(separator: ":").map { String($0) })
        var augmented = currentPath
        for dir in cliSearchPaths {
            if !currentDirs.contains(dir) {
                augmented = "\(dir):\(augmented)"
            }
        }
        env["PATH"] = augmented

        // Set GT_TOWN_ROOT and BEADS_DIR if a town root is available.
        let effectiveTownRoot = townRootPath ?? detectTownRoot()
        if let root = effectiveTownRoot {
            env["GT_TOWN_ROOT"] = root
            env["BEADS_DIR"] = (root as NSString).appendingPathComponent(".beads")
        }

        return env
    }

    // MARK: - Process Execution

    /// Run a process synchronously and capture stdout + stderr.
    ///
    /// Uses the augmented CLI environment so child processes can find
    /// their own dependencies (e.g. gt invoking bd, or bd connecting to Dolt).
    static func runProcess(executablePath: String, arguments: [String], townRootPath: String? = nil) -> CLIResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = cliEnvironment(townRootPath: townRootPath)

        do {
            try process.run()
        } catch {
            return CLIResult(
                exitCode: -1,
                stdout: Data(),
                stderr: Data("Failed to launch process: \(error.localizedDescription)".utf8)
            )
        }

        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return CLIResult(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )
    }

    /// Attempt to find the `gt` binary.
    static func resolveGTCLI() -> String? {
        resolveExecutable("gt")
    }

    /// Attempt to find the `bd` binary.
    static func resolveBDCLI() -> String? {
        resolveExecutable("bd")
    }

    // MARK: - Town Root Detection

    /// Best-effort town root detection for environment setup.
    /// Checks GT_TOWN_ROOT env var, then common paths.
    private static func detectTownRoot() -> String? {
        let env = ProcessInfo.processInfo.environment
        if let root = env["GT_TOWN_ROOT"], !root.isEmpty {
            return root
        }
        if let root = env["GT_ROOT"], !root.isEmpty {
            return root
        }
        // Check common convention paths.
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let candidates = [
            (home as NSString).appendingPathComponent("gt"),
            (home as NSString).appendingPathComponent("code/spectralGasTown"),
        ]
        for candidate in candidates {
            let routesPath = (candidate as NSString).appendingPathComponent(".beads/routes.jsonl")
            if fm.fileExists(atPath: routesPath) {
                return candidate
            }
        }
        return nil
    }
}

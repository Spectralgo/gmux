import Foundation

// MARK: - Gas Town CLI Runner
//
// Shared synchronous process runner and `gt` CLI resolution used by
// adapters that need blocking CLI execution (AgentHealthAdapter,
// ConvoyAdapter, HooksAdapter).
//
// GastownCommandRunner.swift is the *async* runner with timeouts.
// This file is the *sync* counterpart — no async, no timeout, just
// Process + Pipe + waitUntilExit.

enum GasTownCLIRunner {

    /// Result of a synchronous CLI invocation.
    struct CLIResult: Equatable, Sendable {
        let exitCode: Int32
        let stdout: Data
        let stderr: Data
    }

    /// Run a process synchronously and capture stdout + stderr.
    static func runProcess(
        executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) -> CLIResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        if let environment {
            process.environment = environment
        }

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

    /// Find the `gt` binary by searching well-known install locations.
    /// Does not use `/usr/bin/which` — macOS GUI apps have no shell PATH.
    static func resolveGTCLI() -> String? {
        resolveCLI(name: "gt")
    }

    /// Find the `bd` binary by searching well-known install locations.
    static func resolveBDCLI() -> String? {
        resolveCLI(name: "bd")
    }

    private static func resolveCLI(name: String) -> String? {
        let searchPaths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            NSString(string: "~/go/bin/\(name)").expandingTildeInPath,
        ]
        for path in searchPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Build a process environment dict with PATH, BEADS_DIR, and GT_TOWN_ROOT
    /// set so child processes can find Gas Town tooling and data.
    static func processEnvironment(
        townRoot: String?,
        rigBeadsPath: String? = nil
    ) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin"
        if let existing = env["PATH"] {
            env["PATH"] = "\(extraPaths):\(existing)"
        } else {
            env["PATH"] = extraPaths
        }
        if let beadsPath = rigBeadsPath {
            env["BEADS_DIR"] = beadsPath
        } else if let townRoot {
            env["BEADS_DIR"] = (townRoot as NSString).appendingPathComponent(".beads")
        }
        if let townRoot {
            env["GT_TOWN_ROOT"] = townRoot
        }
        return env
    }
}

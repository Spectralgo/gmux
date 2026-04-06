import Foundation

/// Result of executing a Gastown CLI command (`bd` or `gt`).
struct GastownCommandResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let timedOut: Bool

    var succeeded: Bool { exitCode == 0 && !timedOut }
}

/// Runs `bd` and `gt` CLI commands as subprocesses and returns structured results.
///
/// All commands run off the main thread. Callers should dispatch to main
/// for any UI or model updates after receiving results.
enum GastownCommandRunner {

    // MARK: - Public API

    /// Run a `bd` command with the given arguments.
    static func bd(_ arguments: [String], timeoutSeconds: TimeInterval = 30) async -> GastownCommandResult {
        await run(executable: bdPath, arguments: arguments, timeoutSeconds: timeoutSeconds)
    }

    /// Run a `gt` command with the given arguments.
    static func gt(_ arguments: [String], timeoutSeconds: TimeInterval = 30) async -> GastownCommandResult {
        await run(executable: gtPath, arguments: arguments, timeoutSeconds: timeoutSeconds)
    }

    // MARK: - Executable Resolution

    private static let bdPath: String = resolveExecutable("bd")
    private static let gtPath: String = resolveExecutable("gt")

    private static func resolveExecutable(_ name: String) -> String {
        let knownPaths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
        ]
        for path in knownPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return name
    }

    // MARK: - Subprocess Execution

    private static func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) async -> GastownCommandResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            var timedOut = false
            let timeoutWorkItem = DispatchWorkItem {
                timedOut = true
                process.terminate()
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: GastownCommandResult(
                    stdout: "",
                    stderr: "Failed to launch \(executable): \(error.localizedDescription)",
                    exitCode: -1,
                    timedOut: false
                ))
                return
            }

            DispatchQueue.global().asyncAfter(
                deadline: .now() + timeoutSeconds,
                execute: timeoutWorkItem
            )

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            timeoutWorkItem.cancel()

            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""

            continuation.resume(returning: GastownCommandResult(
                stdout: stdout,
                stderr: stderr,
                exitCode: process.terminationStatus,
                timedOut: timedOut
            ))
        }
    }
}

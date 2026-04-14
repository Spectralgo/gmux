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
    static func bd(
        _ arguments: [String],
        townRootPath: String? = nil,
        timeoutSeconds: TimeInterval = 30
    ) async -> GastownCommandResult {
        await run(executable: bdPath, arguments: arguments, townRootPath: townRootPath, timeoutSeconds: timeoutSeconds)
    }

    /// Run a `gt` command with the given arguments.
    static func gt(
        _ arguments: [String],
        townRootPath: String? = nil,
        timeoutSeconds: TimeInterval = 30
    ) async -> GastownCommandResult {
        await run(executable: gtPath, arguments: arguments, townRootPath: townRootPath, timeoutSeconds: timeoutSeconds)
    }

    /// Run an arbitrary executable by name with the given arguments.
    ///
    /// Resolves the executable via `GasTownCLIRunner.resolveExecutable(_:)`
    /// before launching. Returns a failure result if the executable is not found.
    static func exec(
        _ name: String,
        arguments: [String],
        townRootPath: String? = nil,
        timeoutSeconds: TimeInterval = 30
    ) async -> GastownCommandResult {
        guard let path = GasTownCLIRunner.resolveExecutable(name) else {
            return GastownCommandResult(
                stdout: "",
                stderr: "Executable '\(name)' not found",
                exitCode: -1,
                timedOut: false
            )
        }
        return await run(executable: path, arguments: arguments, townRootPath: townRootPath, timeoutSeconds: timeoutSeconds)
    }

    // MARK: - Executable Resolution

    private static let bdPath: String = GasTownCLIRunner.resolveExecutable("bd") ?? "bd"
    private static let gtPath: String = GasTownCLIRunner.resolveExecutable("gt") ?? "gt"

    // MARK: - Subprocess Execution

    private static func run(
        executable: String,
        arguments: [String],
        townRootPath: String?,
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
            process.environment = GasTownCLIRunner.cliEnvironment(townRootPath: townRootPath)

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

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
    static func runProcess(executablePath: String, arguments: [String]) -> CLIResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

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
                let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
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

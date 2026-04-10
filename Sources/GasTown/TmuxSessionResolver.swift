import Foundation

struct TmuxSessionResolver {
    /// Gas Town tmux sockets live at /tmp/tmux-<uid>/spectralgastown-*
    static func findSocket() -> String? {
        let fm = FileManager.default
        let tmpDir = "/tmp"
        guard let entries = try? fm.contentsOfDirectory(atPath: tmpDir) else { return nil }
        for entry in entries where entry.hasPrefix("tmux-") {
            let tmuxDir = "\(tmpDir)/\(entry)"
            guard let sockets = try? fm.contentsOfDirectory(atPath: tmuxDir) else { continue }
            if let match = sockets.first(where: { $0.hasPrefix("spectralgastown-") }) {
                return "\(tmuxDir)/\(match)"
            }
        }
        return nil
    }

    /// Build tmux attach command. Session names: <2-char rig prefix>-<agent name>
    static func attachCommand(agentName: String, rig: String) -> String? {
        guard let socket = findSocket() else { return nil }
        let prefix = String(rig.prefix(2))
        let sessionName = "\(prefix)-\(agentName)"
        return "tmux -S '\(socket)' attach-session -t '\(sessionName)'"
    }

    /// List all active session names from the Gas Town tmux server.
    static func listSessions() -> [String] {
        guard let socket = findSocket() else { return [] }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["tmux", "-S", socket, "list-sessions", "-F", "#{session_name}"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch { return [] }
        guard process.terminationStatus == 0 else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
}

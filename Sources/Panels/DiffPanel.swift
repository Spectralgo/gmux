import Foundation
import Combine

/// Represents a single changed file in a git diff.
struct DiffFileEntry: Identifiable, Equatable {
    let id = UUID()
    let path: String
    let status: String  // "M", "A", "D", "R", "??"
}

/// A panel that displays changed files and diff output for a git repository.
/// Bound to a repository path and optional revision range.
@MainActor
final class DiffPanel: Panel, ObservableObject {
    let id: UUID
    let panelType: PanelType = .diff

    /// Absolute path to the git repository root.
    let repositoryPath: String

    /// Base revision for the diff (e.g. "HEAD", a branch name, or a commit SHA).
    /// When nil, shows unstaged working tree changes.
    let baseRevision: String?

    /// The workspace this panel belongs to.
    private(set) var workspaceId: UUID

    /// List of changed files.
    @Published private(set) var changedFiles: [DiffFileEntry] = []

    /// Currently selected file path for detail view.
    @Published var selectedFilePath: String?

    /// Diff output for the selected file.
    @Published private(set) var selectedFileDiff: String = ""

    /// Summary line (e.g. "3 files changed").
    @Published private(set) var summary: String = ""

    /// Title shown in the tab bar.
    @Published private(set) var displayTitle: String = ""

    /// SF Symbol icon for the tab bar.
    var displayIcon: String? { "doc.text.magnifyingglass" }

    /// Whether loading is in progress.
    @Published private(set) var isLoading: Bool = false

    /// Error message if git commands fail.
    @Published private(set) var errorMessage: String?

    /// Token incremented to trigger focus flash animation.
    @Published private(set) var focusFlashToken: Int = 0

    private var isClosed: Bool = false
    private var selectedFileSubscription: AnyCancellable?

    // MARK: - Init

    init(workspaceId: UUID, repositoryPath: String, baseRevision: String? = nil) {
        self.id = UUID()
        self.workspaceId = workspaceId
        self.repositoryPath = repositoryPath
        self.baseRevision = baseRevision

        let repoName = (repositoryPath as NSString).lastPathComponent
        if let baseRevision {
            self.displayTitle = "\(repoName) (\(baseRevision))"
        } else {
            self.displayTitle = "\(repoName) changes"
        }

        selectedFileSubscription = $selectedFilePath
            .removeDuplicates()
            .sink { [weak self] path in
                guard let self, let path else {
                    self?.selectedFileDiff = ""
                    return
                }
                self.loadFileDiff(path)
            }

        refresh()
    }

    // MARK: - Panel protocol

    func focus() {
        // Read-only panel; no first responder to manage.
    }

    func unfocus() {
        // No-op for read-only panel.
    }

    func close() {
        isClosed = true
        selectedFileSubscription?.cancel()
        selectedFileSubscription = nil
    }

    func triggerFlash(reason: WorkspaceAttentionFlashReason) {
        _ = reason
        guard NotificationPaneFlashSettings.isEnabled() else { return }
        focusFlashToken += 1
    }

    // MARK: - Git operations

    func refresh() {
        guard !isClosed else { return }
        isLoading = true
        errorMessage = nil

        let repoPath = repositoryPath
        let baseRev = baseRevision

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let entries = Self.fetchChangedFiles(repoPath: repoPath, baseRevision: baseRev)
            let summaryText: String
            switch entries {
            case .success(let files):
                let count = files.count
                summaryText = count == 1
                    ? "1 file changed"
                    : "\(count) files changed"
            case .failure(let error):
                summaryText = error.localizedDescription
            }

            DispatchQueue.main.async {
                guard let self, !self.isClosed else { return }
                switch entries {
                case .success(let files):
                    self.changedFiles = files
                    self.summary = summaryText
                    self.errorMessage = nil
                    // Auto-select first file if nothing selected
                    if self.selectedFilePath == nil, let first = files.first {
                        self.selectedFilePath = first.path
                    }
                case .failure(let error):
                    self.changedFiles = []
                    self.summary = ""
                    self.errorMessage = error.localizedDescription
                }
                self.isLoading = false
            }
        }
    }

    private func loadFileDiff(_ filePath: String) {
        guard !isClosed else { return }

        let repoPath = repositoryPath
        let baseRev = baseRevision

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let diff = Self.fetchFileDiff(repoPath: repoPath, filePath: filePath, baseRevision: baseRev)

            DispatchQueue.main.async {
                guard let self, !self.isClosed else { return }
                self.selectedFileDiff = diff
            }
        }
    }

    // MARK: - Git helpers (off-main)

    private static func fetchChangedFiles(repoPath: String, baseRevision: String?) -> Result<[DiffFileEntry], Error> {
        // First get tracked file changes
        var args: [String]
        if let baseRevision {
            args = ["git", "-C", repoPath, "diff", "--name-status", baseRevision]
        } else {
            args = ["git", "-C", repoPath, "diff", "--name-status"]
        }

        let trackedResult = runGitCommand(args)
        guard case .success(let trackedOutput) = trackedResult else {
            if case .failure(let error) = trackedResult {
                return .failure(error)
            }
            return .success([])
        }

        var entries: [DiffFileEntry] = []
        for line in trackedOutput.split(separator: "\n") where !line.isEmpty {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let status = String(parts[0])
            let path = String(parts[1])
            entries.append(DiffFileEntry(path: path, status: status))
        }

        // Also get staged changes if no base revision
        if baseRevision == nil {
            let stagedResult = runGitCommand(["git", "-C", repoPath, "diff", "--name-status", "--cached"])
            if case .success(let stagedOutput) = stagedResult {
                let existingPaths = Set(entries.map(\.path))
                for line in stagedOutput.split(separator: "\n") where !line.isEmpty {
                    let parts = line.split(separator: "\t", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    let path = String(parts[1])
                    guard !existingPaths.contains(path) else { continue }
                    let status = String(parts[0])
                    entries.append(DiffFileEntry(path: path, status: status))
                }
            }

            // Also get untracked files
            let untrackedResult = runGitCommand(["git", "-C", repoPath, "ls-files", "--others", "--exclude-standard"])
            if case .success(let untrackedOutput) = untrackedResult {
                let existingPaths = Set(entries.map(\.path))
                for line in untrackedOutput.split(separator: "\n") where !line.isEmpty {
                    let path = String(line)
                    guard !existingPaths.contains(path) else { continue }
                    entries.append(DiffFileEntry(path: path, status: "??"))
                }
            }
        }

        entries.sort { $0.path < $1.path }
        return .success(entries)
    }

    private static func fetchFileDiff(repoPath: String, filePath: String, baseRevision: String?) -> String {
        // Try staged diff first, then unstaged, then combined
        var diffOutput = ""

        if let baseRevision {
            let result = runGitCommand(["git", "-C", repoPath, "diff", baseRevision, "--", filePath])
            if case .success(let output) = result {
                diffOutput = output
            }
        } else {
            // Show both staged and unstaged changes
            let stagedResult = runGitCommand(["git", "-C", repoPath, "diff", "--cached", "--", filePath])
            let unstagedResult = runGitCommand(["git", "-C", repoPath, "diff", "--", filePath])

            if case .success(let staged) = stagedResult, !staged.isEmpty {
                diffOutput += staged
            }
            if case .success(let unstaged) = unstagedResult, !unstaged.isEmpty {
                if !diffOutput.isEmpty {
                    diffOutput += "\n"
                }
                diffOutput += unstaged
            }

            // If no diff output, the file might be untracked — show its contents
            if diffOutput.isEmpty {
                let fullPath = (repoPath as NSString).appendingPathComponent(filePath)
                if let content = try? String(contentsOfFile: fullPath, encoding: .utf8) {
                    diffOutput = "+++ new file: \(filePath)\n" + content.split(separator: "\n", omittingEmptySubsequences: false).map { "+\($0)" }.joined(separator: "\n")
                }
            }
        }

        return diffOutput
    }

    private static func runGitCommand(_ args: [String]) -> Result<String, Error> {
        let process = Process()
        let pipe = Pipe()
        let errPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .failure(error)
        }

        guard process.terminationStatus == 0 else {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? "git command failed"
            return .failure(NSError(domain: "DiffPanel", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errStr.trimmingCharacters(in: .whitespacesAndNewlines)]))
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return .success(output)
    }
}

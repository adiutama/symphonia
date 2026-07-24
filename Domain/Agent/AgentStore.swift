import Foundation

/// One Agent ↔ one Worktree folder under `<workspace>/worktrees/<three-word>/` (ADR 0003, 0018).
struct AgentSummary: Equatable, Identifiable, Sendable {
    /// Stable id = absolute Worktree path (folder is on-disk identity).
    var id: String { worktreeURL.path }

    /// Three-Word Name folder under `worktrees/`.
    var threeWordName: String

    /// Absolute Worktree checkout URL.
    var worktreeURL: URL

    /// Best-effort current branch (`git branch --show-current`); may be nil / empty for detached HEAD.
    var branchName: String?
}

/// Create / list / remove Agent Worktrees via `git worktree` (ADR 0003, 0017–0020).
struct AgentStore: Sendable {
    enum StoreError: LocalizedError, Equatable {
        case noWorkspace
        case mainNotGitRepo(URL)
        case alreadyExists(URL)
        case missingWorktree(URL)
        case baseRefNotFound(String)
        case gitFailed(String)
        case invalidBranchName(String)

        var errorDescription: String? {
            switch self {
            case .noWorkspace:
                return "Select a Workspace before creating a Worktree."
            case .mainNotGitRepo(let url):
                return "Main Repo is not a git repository: \(url.path)"
            case .alreadyExists(let url):
                return "Worktree already exists: \(url.path)"
            case .missingWorktree(let url):
                return "Worktree not found: \(url.path)"
            case .baseRefNotFound(let ref):
                return "Base Ref “\(ref)” not found in Main Repo. Commit or set Base Ref in Settings."
            case .gitFailed(let detail):
                return "git failed: \(detail)"
            case .invalidBranchName(let name):
                return "Invalid branch name “\(name)”."
            }
        }
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - List

    /// List Agent folders under the Workspace’s `worktrees/` directory.
    func list(workspaceDataDir: URL) throws -> [AgentSummary] {
        let worktreesDir = SymphoniaPaths.workspaceWorktreesDirectory(in: workspaceDataDir)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: worktreesDir.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }

        let contents = try fileManager.contentsOfDirectory(
            at: worktreesDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var agents: [AgentSummary] = []
        for child in contents {
            var childIsDir: ObjCBool = false
            guard fileManager.fileExists(atPath: child.path, isDirectory: &childIsDir),
                  childIsDir.boolValue
            else { continue }

            let name = child.lastPathComponent
            let branch = try? currentBranch(at: child)
            agents.append(
                AgentSummary(
                    threeWordName: name,
                    worktreeURL: child.standardizedFileURL,
                    branchName: branch
                )
            )
        }

        return agents.sorted {
            $0.threeWordName.localizedCaseInsensitiveCompare($1.threeWordName) == .orderedAscending
        }
    }

    /// Existing Three-Word folder names under `worktrees/` (for collision checks).
    func existingFolderNames(workspaceDataDir: URL) throws -> Set<String> {
        Set(try list(workspaceDataDir: workspaceDataDir).map(\.threeWordName))
    }

    // MARK: - Create

    /// Create an Agent: `git worktree add` under `worktrees/<threeWordName>/`.
    ///
    /// - Parameters:
    ///   - workspaceDataDir: Workspace Data Dir containing `main/` and `worktrees/`.
    ///   - threeWordName: Folder name (auto Three-Word Name).
    ///   - branchName: New branch name (default = folder name when caller passes the same).
    ///   - baseRef: Effective Base Ref to branch from (ADR 0019).
    @discardableResult
    func create(
        workspaceDataDir: URL,
        threeWordName: String,
        branchName: String,
        baseRef: String
    ) throws -> AgentSummary {
        let mainDir = SymphoniaPaths.workspaceMainDirectory(in: workspaceDataDir)
        let worktreesDir = SymphoniaPaths.workspaceWorktreesDirectory(in: workspaceDataDir)
        let worktreeURL = SymphoniaPaths.agentWorktreeDirectory(
            in: workspaceDataDir,
            threeWordName: threeWordName
        )

        guard isGitRepository(mainDir) else {
            throw StoreError.mainNotGitRepo(mainDir)
        }

        let branch = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty, isValidGitRefName(branch) else {
            throw StoreError.invalidBranchName(branchName)
        }

        if fileManager.fileExists(atPath: worktreeURL.path) {
            throw StoreError.alreadyExists(worktreeURL)
        }

        try fileManager.createDirectory(at: worktreesDir, withIntermediateDirectories: true)

        let startPoint = try resolveStartPoint(mainDir: mainDir, baseRef: baseRef)

        // `git worktree add -b <branch> <path> [<start-point>]`
        var args = ["worktree", "add", "-b", branch, worktreeURL.path]
        if let startPoint {
            args.append(startPoint)
        }

        try runGit(args, in: mainDir)

        let resolvedBranch = (try? currentBranch(at: worktreeURL)) ?? branch
        return AgentSummary(
            threeWordName: threeWordName,
            worktreeURL: worktreeURL.standardizedFileURL,
            branchName: resolvedBranch
        )
    }

    // MARK: - Remove

    /// Remove Agent Worktree folder + git registration; **keeps** the branch by default (ADR 0020).
    ///
    /// - Parameter deleteBranch: When true, also `git branch -D` after worktree removal.
    func remove(
        workspaceDataDir: URL,
        agent: AgentSummary,
        deleteBranch: Bool = false
    ) throws {
        let mainDir = SymphoniaPaths.workspaceMainDirectory(in: workspaceDataDir)
        guard isGitRepository(mainDir) else {
            throw StoreError.mainNotGitRepo(mainDir)
        }

        let path = agent.worktreeURL.path
        guard fileManager.fileExists(atPath: path) else {
            throw StoreError.missingWorktree(agent.worktreeURL)
        }

        let branchToDelete = deleteBranch ? (agent.branchName ?? agent.threeWordName) : nil

        // Prefer registered remove; fall back to force, then prune + rmdir.
        do {
            try runGit(["worktree", "remove", path], in: mainDir)
        } catch {
            do {
                try runGit(["worktree", "remove", "--force", path], in: mainDir)
            } catch {
                try runGit(["worktree", "prune"], in: mainDir)
                if fileManager.fileExists(atPath: path) {
                    try fileManager.removeItem(at: agent.worktreeURL)
                }
            }
        }

        if let branchToDelete, !branchToDelete.isEmpty {
            // Best-effort; ignore failure if branch is checked out elsewhere or protected.
            try? runGit(["branch", "-D", branchToDelete], in: mainDir)
        }
    }

    // MARK: - Private

    private func resolveStartPoint(mainDir: URL, baseRef: String) throws -> String? {
        let trimmed = baseRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw StoreError.baseRefNotFound(baseRef)
        }

        if refExists(trimmed, in: mainDir) {
            return trimmed
        }

        // Unborn HEAD (fresh `git init`): allow `worktree add -b` without start-point.
        if !hasCommits(in: mainDir) {
            return nil
        }

        throw StoreError.baseRefNotFound(trimmed)
    }

    private func isGitRepository(_ mainDir: URL) -> Bool {
        fileManager.fileExists(atPath: mainDir.appendingPathComponent(".git").path)
    }

    private func hasCommits(in mainDir: URL) -> Bool {
        (try? runGitCapturing(["rev-parse", "--verify", "HEAD"], in: mainDir)) != nil
    }

    private func refExists(_ ref: String, in mainDir: URL) -> Bool {
        (try? runGitCapturing(["rev-parse", "--verify", "\(ref)^{commit}"], in: mainDir)) != nil
    }

    private func currentBranch(at worktree: URL) throws -> String? {
        let output = try runGitCapturing(["branch", "--show-current"], in: worktree)
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func isValidGitRefName(_ name: String) -> Bool {
        // Reject path traversal / whitespace / obvious git-check-ref-format failures.
        if name.hasPrefix(".") || name.hasSuffix(".") || name.hasSuffix(".lock") { return false }
        if name.contains("..") || name.contains(" ") || name.contains("~") || name.contains("^") {
            return false
        }
        if name.contains(":") || name.contains("?") || name.contains("*") || name.contains("[") {
            return false
        }
        if name.contains("\\") || name.contains("\0") || name.contains("@{") { return false }
        if name == "@" || name.isEmpty { return false }
        return true
    }

    private func runGit(_ arguments: [String], in directory: URL) throws {
        _ = try runGitCapturing(arguments, in: directory)
    }

    @discardableResult
    private func runGitCapturing(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw StoreError.gitFailed(error.localizedDescription)
        }

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            let detail = err.isEmpty ? "exit \(process.terminationStatus)" : err
            throw StoreError.gitFailed(detail)
        }

        return out
    }
}

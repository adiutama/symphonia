import Foundation

/// One Agent ↔ one Worktree folder, a **sibling of `main/`** under `<workspace>/<three-word>/`
/// (ADR 0003, 0014, 0018 — flattened in P1.5).
struct AgentSummary: Equatable, Identifiable, Sendable {
    /// Stable id = absolute Worktree path (folder is on-disk identity).
    var id: String { worktreeURL.path }

    /// Three-Word Name folder, sibling of `main/` in the Workspace Data Dir.
    var threeWordName: String

    /// Absolute Worktree checkout URL.
    var worktreeURL: URL

    /// Best-effort current branch (`git branch --show-current`); may be nil / empty for detached HEAD.
    var branchName: String?
}

/// Create / list / remove Agent Worktrees via `git worktree` (ADR 0003, 0014, 0017–0020).
struct AgentStore: Sendable {
    enum StoreError: LocalizedError, Equatable {
        case noWorkspace
        case mainNotGitRepo(URL)
        case alreadyExists(URL)
        case missingWorktree(URL)
        case baseRefNotFound(String)
        case gitFailed(String)
        case invalidBranchName(String)
        case reservedName(String)

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
            case .reservedName(let name):
                return "“\(name)” is reserved for Main and cannot be used as a Worktree name."
            }
        }
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - List

    /// List Worktree folders that are **siblings of `main/`** directly under the Workspace Data
    /// Dir (P1.5 flat layout). Skips `main/` (`SymphoniaPaths.reservedWorkspaceChildNames`) and
    /// any non-git-checkout directory so stray folders never show up as Agents.
    func list(workspaceDataDir: URL) throws -> [AgentSummary] {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: workspaceDataDir.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }

        let contents = try fileManager.contentsOfDirectory(
            at: workspaceDataDir,
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
            guard !SymphoniaPaths.reservedWorkspaceChildNames.contains(name.lowercased()) else { continue }
            // A Worktree checkout always has a `.git` file (linking back to Main's git dir);
            // skip anything else so unrelated sibling folders are never mistaken for Agents.
            guard isGitRepository(child) else { continue }

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

    /// Best-effort current branch for a checkout (`git branch --show-current`).
    /// Used by the HEAD file watcher to refresh sidebar labels without a full list rebuild.
    func readCurrentBranch(at worktree: URL) -> String? {
        try? currentBranch(at: worktree)
    }

    /// Every top-level name (file or directory) already present in the Workspace Data Dir — used
    /// for Three-Word Name collision checks so a fresh/Operator-edited name can never collide with
    /// `main/`, `config.json`, another Worktree, or anything else already there (P1.5 flat siblings).
    func existingFolderNames(workspaceDataDir: URL) throws -> Set<String> {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: workspaceDataDir.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }

        let contents = try fileManager.contentsOfDirectory(
            at: workspaceDataDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return Set(contents.map(\.lastPathComponent))
    }

    // MARK: - Create

    /// Create an Agent: `git worktree add` as a **sibling of `main/`** — `<workspaceDataDir>/<threeWordName>/`.
    ///
    /// - Parameters:
    ///   - workspaceDataDir: Workspace Data Dir containing `main/` and sibling Worktree folders.
    ///   - threeWordName: Folder name (auto Three-Word Name); refused when reserved (`main`).
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
        let worktreeURL = SymphoniaPaths.workspaceWorktreeDirectory(
            in: workspaceDataDir,
            threeWordName: threeWordName
        )

        guard isGitRepository(mainDir) else {
            throw StoreError.mainNotGitRepo(mainDir)
        }

        let trimmedName = threeWordName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !SymphoniaPaths.reservedWorkspaceChildNames.contains(trimmedName.lowercased()) else {
            throw StoreError.reservedName(threeWordName)
        }

        let branch = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty, isValidGitRefName(branch) else {
            throw StoreError.invalidBranchName(branchName)
        }

        if fileManager.fileExists(atPath: worktreeURL.path) {
            throw StoreError.alreadyExists(worktreeURL)
        }

        let startPoint = try resolveStartPoint(mainDir: mainDir, baseRef: baseRef)

        // `git worktree add -b <branch> <path> [<start-point>]` — `workspaceDataDir` (the parent)
        // already exists, so git creates the leaf checkout dir itself; no separate mkdir needed.
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
    /// Refuses `main` even if a caller somehow constructs an `AgentSummary` for it directly —
    /// Main is protected at every layer, not just the UI (P1.5).
    ///
    /// - Parameter deleteBranch: When true, also `git branch -D` after worktree removal.
    func remove(
        workspaceDataDir: URL,
        agent: AgentSummary,
        deleteBranch: Bool = false
    ) throws {
        guard !SymphoniaPaths.reservedWorkspaceChildNames.contains(agent.threeWordName.lowercased()) else {
            throw StoreError.reservedName(agent.threeWordName)
        }

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

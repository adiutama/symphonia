import Foundation

/// One Worktree ↔ one Worktree folder, a **sibling of `main/`** under `<workspace>/<three-word>/`
/// (ADR 0003, 0014, 0018 — flattened in P1.5).
struct WorktreeSummary: Equatable, Identifiable, Sendable {
    /// Stable id = absolute Worktree path (folder is on-disk identity).
    var id: String { worktreeURL.path }

    /// Three-Word Name folder, sibling of `main/` in the Workspace Data Dir.
    var threeWordName: String

    /// Absolute Worktree checkout URL.
    var worktreeURL: URL

    /// Best-effort current branch (`git branch --show-current`); may be nil / empty for detached HEAD.
    var branchName: String?
}

/// Create / list / remove Worktrees via `git worktree` (ADR 0003, 0014, 0017–0020).
struct WorktreeStore: @unchecked Sendable {
    enum StoreError: LocalizedError, Equatable {
        case noWorkspace
        case mainNotGitRepo(URL)
        case alreadyExists(URL)
        case missingWorktree(URL)
        case baseRefNotFound(String)
        case mainHasNoCommits
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
            case .mainHasNoCommits:
                return "Main has no commits yet — not a bug. Make a commit in Main CLI first, then try again."
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
    /// any non-git-checkout directory so stray folders never show up as Worktrees.
    func list(workspaceDataDir: URL) throws -> [WorktreeSummary] {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: workspaceDataDir.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }

        let contents = try fileManager.contentsOfDirectory(
            at: workspaceDataDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var worktrees: [WorktreeSummary] = []
        for child in contents {
            var childIsDir: ObjCBool = false
            guard fileManager.fileExists(atPath: child.path, isDirectory: &childIsDir),
                  childIsDir.boolValue
            else { continue }

            let name = child.lastPathComponent
            guard !SymphoniaPaths.reservedWorkspaceChildNames.contains(name.lowercased()) else { continue }
            // A Worktree checkout always has a `.git` file (linking back to Main's git dir);
            // skip anything else so unrelated sibling folders are never mistaken for Worktrees.
            guard isGitRepository(child) else { continue }

            let branch = try? currentBranch(at: child)
            worktrees.append(
                WorktreeSummary(
                    threeWordName: name,
                    worktreeURL: child.standardizedFileURL,
                    branchName: branch
                )
            )
        }

        return worktrees.sorted {
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
    /// `main/`, `config.toml`, another Worktree, or anything else already there (P1.5 flat siblings).
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

    /// Create a Worktree: `git worktree add` as a **sibling of `main/`** — `<workspaceDataDir>/<threeWordName>/`.
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
    ) throws -> WorktreeSummary {
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

        // `git worktree add` needs a real commit; fresh Local Main is unborn until first commit.
        guard mainHasCommits(workspaceDataDir: workspaceDataDir) else {
            throw StoreError.mainHasNoCommits
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
        return WorktreeSummary(
            threeWordName: threeWordName,
            worktreeURL: worktreeURL.standardizedFileURL,
            branchName: resolvedBranch
        )
    }

    // MARK: - Rename

    /// Rename branch and/or folder for one Worktree (ADR 0018).
    ///
    /// Pass the Operator-edited branch and folder names; unchanged values are no-ops.
    /// Branch: `git branch -m` in the checkout. Folder: `git worktree move`.
    func rename(
        workspaceDataDir: URL,
        agent: WorktreeSummary,
        newBranchName: String,
        newFolderName: String
    ) throws -> WorktreeSummary {
        let mainDir = SymphoniaPaths.workspaceMainDirectory(in: workspaceDataDir)
        guard isGitRepository(mainDir) else {
            throw StoreError.mainNotGitRepo(mainDir)
        }

        guard !SymphoniaPaths.reservedWorkspaceChildNames.contains(agent.threeWordName.lowercased()) else {
            throw StoreError.reservedName(agent.threeWordName)
        }

        let trimmedBranch = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFolder = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)

        let existingBranch = agent.branchName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let branchChanged = !trimmedBranch.isEmpty && trimmedBranch != existingBranch
        let folderChanged = !trimmedFolder.isEmpty && trimmedFolder != agent.threeWordName

        guard branchChanged || folderChanged else {
            return agent
        }

        if branchChanged {
            guard isValidGitRefName(trimmedBranch) else {
                throw StoreError.invalidBranchName(trimmedBranch)
            }
        }

        var validatedFolder = agent.threeWordName
        if folderChanged {
            switch WorkspaceSlug.validate(trimmedFolder) {
            case .success(let slug):
                validatedFolder = slug
            case .failure(let error):
                throw StoreError.invalidBranchName(error.localizedDescription)
            }

            let existing = try existingFolderNames(workspaceDataDir: workspaceDataDir)
            if existing.contains(validatedFolder) {
                throw StoreError.alreadyExists(
                    SymphoniaPaths.workspaceWorktreeDirectory(
                        in: workspaceDataDir,
                        threeWordName: validatedFolder
                    )
                )
            }
        }

        guard fileManager.fileExists(atPath: agent.worktreeURL.path) else {
            throw StoreError.missingWorktree(agent.worktreeURL)
        }

        var worktreeURL = agent.worktreeURL

        if branchChanged {
            try runGit(["branch", "-m", trimmedBranch], in: worktreeURL)
        }

        if folderChanged {
            let newURL = SymphoniaPaths.workspaceWorktreeDirectory(
                in: workspaceDataDir,
                threeWordName: validatedFolder
            )
            try runGit(["worktree", "move", worktreeURL.path, newURL.path], in: mainDir)
            worktreeURL = newURL.standardizedFileURL
        }

        let resolvedBranch = (try? currentBranch(at: worktreeURL)) ?? (branchChanged ? trimmedBranch : agent.branchName)
        return WorktreeSummary(
            threeWordName: folderChanged ? validatedFolder : agent.threeWordName,
            worktreeURL: worktreeURL,
            branchName: resolvedBranch
        )
    }

    // MARK: - Remove

    /// Remove Worktree folder + git registration; **keeps** the branch by default (ADR 0020).
    /// Refuses `main` even if a caller somehow constructs an `WorktreeSummary` for it directly —
    /// Main is protected at every layer, not just the UI (P1.5).
    ///
    /// - Parameter deleteBranch: When true, also `git branch -D` after worktree removal.
    func remove(
        workspaceDataDir: URL,
        agent: WorktreeSummary,
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

    /// Whether Main has at least one commit (`HEAD` resolves). Fresh `git init` is unborn.
    func mainHasCommits(workspaceDataDir: URL) -> Bool {
        let mainDir = SymphoniaPaths.workspaceMainDirectory(in: workspaceDataDir)
        guard isGitRepository(mainDir) else { return false }
        return hasCommits(in: mainDir)
    }

    private func resolveStartPoint(mainDir: URL, baseRef: String) throws -> String? {
        let trimmed = baseRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw StoreError.baseRefNotFound(baseRef)
        }

        if refExists(trimmed, in: mainDir) {
            return trimmed
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

        // Drain pipes while waiting so a chatty git can't fill the 64KB pipe buffer
        // and deadlock (parent in waitUntilExit, child blocked on write).
        let outBox = PipeDrain()
        let errBox = PipeDrain()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            outBox.append(handle.availableData)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            errBox.append(handle.availableData)
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            throw StoreError.gitFailed(error.localizedDescription)
        }

        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        // Pick up any trailing bytes after handlers are cleared.
        outBox.append(stdout.fileHandleForReading.readDataToEndOfFile())
        errBox.append(stderr.fileHandleForReading.readDataToEndOfFile())

        let out = String(data: outBox.data, encoding: .utf8) ?? ""
        let err = String(data: errBox.data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationReason == .uncaughtSignal {
            let signal = process.terminationStatus
            let detail = err.isEmpty ? "git aborted (signal \(signal))" : "git aborted (signal \(signal)): \(err)"
            throw StoreError.gitFailed(detail)
        }

        guard process.terminationStatus == 0 else {
            let detail = err.isEmpty ? "exit \(process.terminationStatus)" : err
            throw StoreError.gitFailed(detail)
        }

        return out
    }
}

/// Thread-safe accumulator for `Pipe` readability handlers.
private final class PipeDrain: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        buffer.append(chunk)
        lock.unlock()
    }
}

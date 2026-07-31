import Foundation

/// On-disk Workspace Data Dir create / layout / list (ADR 0012, 0014, 0015).
///
/// Create runs `git init` in `main/` by default so dogfooding works immediately, or
/// `git clone <url>` when a Clone URL is supplied (P1.4) — the remote URL is then persisted
/// on `config.toml` (`mainRemoteURL`) so `open(at:)` can heal `main/` (P1.5) if it ever goes
/// missing or stops being a git repo: re-clone when a remote URL is known, else `git init`.
/// Clone-later: Operator may also replace `main/` with a CLI clone into that same path.
/// Opening an externally prepared `main/` is supported — layout ensure does not touch an
/// existing repo, and healing is a no-op once Main is a valid git repo. Worktree checkouts are
/// **siblings** of `main/` directly under the Workspace Data Dir (P1.5 flat layout; no
/// `worktrees/` parent) — created lazily by `WorktreeStore`, not by this store.
struct WorkspaceStore: @unchecked Sendable {
    enum StoreError: LocalizedError, Equatable {
        case invalidSlug(String)
        case alreadyExists(URL)
        case missingConfig(URL)
        case notAWorkspace(URL)
        case gitInitFailed(String)
        case gitCloneFailed(String)
        case removeFailed(String)
        case renameFailed(String)
        case relocateFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidSlug(let message):
                return message
            case .alreadyExists(let url):
                return "Workspace Data Dir already exists: \(url.path)"
            case .missingConfig(let url):
                return "Missing config.toml at \(url.path)"
            case .notAWorkspace(let url):
                return "Not a Workspace Data Dir: \(url.path)"
            case .gitInitFailed(let detail):
                return "git init failed: \(detail)"
            case .gitCloneFailed(let detail):
                return "git clone failed: \(detail)"
            case .removeFailed(let detail):
                return "Could not remove Workspace: \(detail)"
            case .renameFailed(let detail):
                return "Could not rename Workspace: \(detail)"
            case .relocateFailed(let detail):
                return "Could not move Workspace Data Dir: \(detail)"
            }
        }
    }

    private let fileManager: FileManager
    private let indexURL: URL

    init(
        fileManager: FileManager = .default,
        indexURL: URL = SymphoniaPaths.workspaceIndexFile
    ) {
        self.fileManager = fileManager
        self.indexURL = indexURL
    }

    // MARK: - Paths

    /// Resolve Workspace Data Dir URL for a slug + optional Prefix override.
    func dataDirURL(slug: String, prefix: String?, workspacesRoot: String) -> URL {
        let parent = SymphoniaPaths.expandingTildeInPath(prefix ?? workspacesRoot)
        return parent.appendingPathComponent(slug, isDirectory: true)
    }

    // MARK: - Create / layout

    /// Create a Workspace container: layout files/dirs, optional Prefix in config.
    ///
    /// When `cloneURL` is non-empty, `main/` is populated with `git clone <cloneURL>` and the
    /// remote URL is persisted on `config.toml` (`mainRemoteURL`) for future heal-on-open
    /// (P1.5). Otherwise `main/` is `git init`’d as before.
    @discardableResult
    func create(
        slug rawSlug: String,
        prefix rawPrefix: String?,
        workspacesRoot: String,
        cloneURL rawCloneURL: String? = nil
    ) throws -> WorkspaceSummary {
        let slug = try validatedSlug(rawSlug)
        let prefix = normalizedOptionalPath(rawPrefix)
        let cloneURL = normalizedOptionalPath(rawCloneURL)
        let dataDir = dataDirURL(slug: slug, prefix: prefix, workspacesRoot: workspacesRoot)

        if fileManager.fileExists(atPath: dataDir.path) {
            throw StoreError.alreadyExists(dataDir)
        }

        try fileManager.createDirectory(at: dataDir, withIntermediateDirectories: true)

        let config = WorkspaceConfig(slug: slug, prefix: prefix, mainRemoteURL: cloneURL)
        try writeConfig(config, to: dataDir)
        try ensureLayout(at: dataDir, initializeMainRepo: cloneURL == nil, cloneRemoteURL: cloneURL)

        try registerInIndex(slug: slug, prefix: prefix)
        return try summary(for: dataDir, fallbackSlug: slug, fallbackPrefix: prefix)
    }

    /// Ensure `config.toml`, `secrets.toml` (0600), and `main/` exist (P1.5: no `worktrees/`
    /// parent — Worktree checkouts are created lazily as siblings of `main/` by `WorktreeStore`).
    /// When `main/` is not yet a git repo: clone `cloneRemoteURL` if given, else `git init` when
    /// `initializeMainRepo` is true.
    func ensureLayout(at dataDir: URL, initializeMainRepo: Bool, cloneRemoteURL: String? = nil) throws {
        try fileManager.createDirectory(at: dataDir, withIntermediateDirectories: true)

        let configURL = SymphoniaPaths.workspaceConfigFile(in: dataDir)
        if !fileManager.fileExists(atPath: configURL.path) {
            let slug = dataDir.lastPathComponent
            try writeConfig(WorkspaceConfig(slug: slug), to: dataDir)
        }

        try SecretStore().ensureStoreFile(in: dataDir)

        let mainDir = SymphoniaPaths.workspaceMainDirectory(in: dataDir)
        try fileManager.createDirectory(at: mainDir, withIntermediateDirectories: true)

        if !isGitRepository(mainDir) {
            if let cloneRemoteURL {
                try gitClone(remoteURL: cloneRemoteURL, into: mainDir)
            } else if initializeMainRepo {
                try gitInit(at: mainDir)
            }
        }
    }

    /// Open an existing Workspace Data Dir (CLI-prepared `main/` is fine). Heals `main/` (P1.5)
    /// when it went missing or stopped being a git repo — re-clone from the persisted remote URL
    /// when present, else `git init`; idempotent no-op when Main is already a valid git repo.
    func open(at dataDir: URL) throws -> WorkspaceSummary {
        let configURL = SymphoniaPaths.workspaceConfigFile(in: dataDir)
        guard fileManager.fileExists(atPath: configURL.path) else {
            throw StoreError.missingConfig(configURL)
        }

        // Do not force-init main/ here — Operator may have cloned externally. ensureLayout only
        // creates the directory if missing; healMainIfNeeded repairs it if it isn't a git repo.
        try ensureLayout(at: dataDir, initializeMainRepo: false)
        let config = try loadConfig(from: dataDir)
        try healMainIfNeeded(at: dataDir, config: config)
        try registerInIndex(slug: config.slug, prefix: config.prefix)
        return try summary(for: dataDir, fallbackSlug: config.slug, fallbackPrefix: config.prefix)
    }

    /// Heal Main (P1.5): if `main/` is missing or not a git repo, re-clone from
    /// `config.mainRemoteURL` when non-empty, else `git init` (same as an empty local Workspace).
    /// No-op — and does not touch disk — when `main/` is already a git repo.
    @discardableResult
    func healMainIfNeeded(at dataDir: URL, config: WorkspaceConfig) throws -> Bool {
        let mainDir = SymphoniaPaths.workspaceMainDirectory(in: dataDir)
        guard !isGitRepository(mainDir) else { return false }

        try fileManager.createDirectory(at: mainDir, withIntermediateDirectories: true)

        let remoteURL = config.mainRemoteURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !remoteURL.isEmpty {
            try gitClone(remoteURL: remoteURL, into: mainDir)
        } else {
            try gitInit(at: mainDir)
        }
        return true
    }

    // MARK: - Config I/O

    func loadConfig(from dataDir: URL) throws -> WorkspaceConfig {
        let url = SymphoniaPaths.workspaceConfigFile(in: dataDir)
        guard fileManager.fileExists(atPath: url.path) else {
            throw StoreError.missingConfig(url)
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        return try PreferencesToml.decodeWorkspaceConfig(from: text)
    }

    func writeConfig(_ config: WorkspaceConfig, to dataDir: URL) throws {
        try fileManager.createDirectory(at: dataDir, withIntermediateDirectories: true)
        let text = PreferencesToml.encode(config)
        try text.write(
            to: SymphoniaPaths.workspaceConfigFile(in: dataDir),
            atomically: true,
            encoding: .utf8
        )
    }

    // MARK: - List

    /// List Workspaces under Workspaces Root plus known Prefixes from the index.
    func list(workspacesRoot: String) throws -> [WorkspaceSummary] {
        var byPath: [String: WorkspaceSummary] = [:]

        let rootURL = SymphoniaPaths.expandingTildeInPath(workspacesRoot)
        try scanPrefixDirectory(rootURL, storedPrefix: nil, into: &byPath)

        let index = loadIndex()
        var knownPrefixes = Set(index.entries.compactMap(\.prefix))
        // Also re-scan prefixes discovered from configs under the default root.
        for summary in byPath.values {
            if let prefix = summary.prefix {
                knownPrefixes.insert(prefix)
            }
        }

        for prefix in knownPrefixes {
            let parent = SymphoniaPaths.expandingTildeInPath(prefix)
            // Skip if this is the same as the already-scanned Workspaces Root.
            if parent.standardizedFileURL.path == rootURL.standardizedFileURL.path {
                continue
            }
            try scanPrefixDirectory(parent, storedPrefix: prefix, into: &byPath)
        }

        // Include index entries that point at dirs we have not scanned yet (sparse).
        for entry in index.entries {
            let dataDir = dataDirURL(slug: entry.slug, prefix: entry.prefix, workspacesRoot: workspacesRoot)
            if byPath[dataDir.path] == nil,
               fileManager.fileExists(atPath: SymphoniaPaths.workspaceConfigFile(in: dataDir).path)
            {
                if let summary = try? summary(
                    for: dataDir,
                    fallbackSlug: entry.slug,
                    fallbackPrefix: entry.prefix
                ) {
                    byPath[dataDir.path] = summary
                }
            }
        }

        return byPath.values.sorted { $0.slug.localizedCaseInsensitiveCompare($1.slug) == .orderedAscending }
    }

    // MARK: - Rename

    /// Rename Workspace slug and move the Workspace Data Dir on disk (ADR 0013, 0015).
    /// Updates `config.toml`, the session index, and `lastSelectedSlug` when it matched the old slug.
    func rename(
        summary: WorkspaceSummary,
        newSlug rawNewSlug: String,
        workspacesRoot: String
    ) throws -> WorkspaceSummary {
        let newSlug = try validatedSlug(rawNewSlug)
        guard newSlug != summary.slug else {
            return summary
        }

        let prefix = summary.prefix
        let oldDataDir = summary.dataDirURL.standardizedFileURL
        let newDataDir = dataDirURL(slug: newSlug, prefix: prefix, workspacesRoot: workspacesRoot)
            .standardizedFileURL

        if fileManager.fileExists(atPath: newDataDir.path) {
            throw StoreError.alreadyExists(newDataDir)
        }

        do {
            try fileManager.moveItem(at: oldDataDir, to: newDataDir)
        } catch {
            throw StoreError.renameFailed(error.localizedDescription)
        }

        var config = try loadConfig(from: newDataDir)
        config.slug = newSlug
        try writeConfig(config, to: newDataDir)

        try updateIndexAfterRename(
            from: summary,
            newSlug: newSlug,
            prefix: prefix,
            workspacesRoot: workspacesRoot
        )

        return try self.summary(for: newDataDir, fallbackSlug: newSlug, fallbackPrefix: prefix)
    }

    // MARK: - Persist Settings / Prefix relocate

    /// Write Workspace Setting overrides into `config.toml`. When the resolved Prefix parent
    /// changes, moves `<oldPrefix>/<slug>` → `<newPrefix>/<slug>` and updates the session index
    /// (same pattern as `rename`). No-op move when normalized parent paths are equal.
    @discardableResult
    func persistSettings(
        summary: WorkspaceSummary,
        overrides: WorkspaceSettingOverrides,
        workspacesRoot: String
    ) throws -> WorkspaceSummary {
        let newPrefix = normalizedOptionalPath(overrides.workspacesRoot)
        let oldParent = SymphoniaPaths.expandingTildeInPath(summary.prefix ?? workspacesRoot)
            .standardizedFileURL
        let newParent = SymphoniaPaths.expandingTildeInPath(newPrefix ?? workspacesRoot)
            .standardizedFileURL
        let oldDataDir = summary.dataDirURL.standardizedFileURL

        guard oldParent.path != newParent.path else {
            var config = try loadConfig(from: oldDataDir)
            config.apply(overrides: overrides)
            config.slug = summary.slug
            try writeConfig(config, to: oldDataDir)
            if summary.prefix != newPrefix {
                try updateIndexAfterRename(
                    from: summary,
                    newSlug: summary.slug,
                    prefix: newPrefix,
                    workspacesRoot: workspacesRoot
                )
            }
            return try self.summary(
                for: oldDataDir,
                fallbackSlug: summary.slug,
                fallbackPrefix: newPrefix
            )
        }

        let newDataDir = dataDirURL(
            slug: summary.slug,
            prefix: newPrefix,
            workspacesRoot: workspacesRoot
        ).standardizedFileURL

        if fileManager.fileExists(atPath: newDataDir.path) {
            throw StoreError.alreadyExists(newDataDir)
        }

        try fileManager.createDirectory(at: newParent, withIntermediateDirectories: true)

        do {
            try fileManager.moveItem(at: oldDataDir, to: newDataDir)
        } catch {
            throw StoreError.relocateFailed(error.localizedDescription)
        }

        var config = try loadConfig(from: newDataDir)
        config.apply(overrides: overrides)
        config.slug = summary.slug
        do {
            try writeConfig(config, to: newDataDir)
        } catch {
            // Heal: attempt to move back so disk stays consistent with the old index entry.
            try? fileManager.moveItem(at: newDataDir, to: oldDataDir)
            throw StoreError.relocateFailed(error.localizedDescription)
        }

        try updateIndexAfterRename(
            from: summary,
            newSlug: summary.slug,
            prefix: newPrefix,
            workspacesRoot: workspacesRoot
        )

        return try self.summary(
            for: newDataDir,
            fallbackSlug: summary.slug,
            fallbackPrefix: newPrefix
        )
    }

    // MARK: - Remove

    /// Permanently delete the Workspace Data Dir from disk and drop it from the session index.
    /// Secrets, Main, Worktrees, and config all live under that directory — nothing is left behind.
    func remove(_ summary: WorkspaceSummary, workspacesRoot: String) throws {
        let dataDir = summary.dataDirURL.standardizedFileURL
        if fileManager.fileExists(atPath: dataDir.path) {
            do {
                try fileManager.removeItem(at: dataDir)
            } catch {
                throw StoreError.removeFailed(error.localizedDescription)
            }
        }
        try unregisterFromIndex(matching: summary, workspacesRoot: workspacesRoot)
    }

    // MARK: - Session index

    func lastSelectedSlug() -> String? {
        loadIndex().lastSelectedSlug
    }

    func setLastSelectedSlug(_ slug: String?) throws {
        var index = loadIndex()
        index.lastSelectedSlug = slug
        try writeIndex(index)
    }

    // MARK: - Private

    private func validatedSlug(_ raw: String) throws -> String {
        switch WorkspaceSlug.validate(raw) {
        case .success(let slug):
            return slug
        case .failure(let error):
            throw StoreError.invalidSlug(error.localizedDescription)
        }
    }

    private func normalizedOptionalPath(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func isGitRepository(_ mainDir: URL) -> Bool {
        let gitDir = mainDir.appendingPathComponent(".git")
        return fileManager.fileExists(atPath: gitDir.path)
    }

    private func gitInit(at mainDir: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init"]
        process.currentDirectoryURL = mainDir
        let stderr = Pipe()
        process.standardOutput = Pipe()
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw StoreError.gitInitFailed(error.localizedDescription)
        }

        guard process.terminationStatus == 0 else {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let detail, !detail.isEmpty {
                throw StoreError.gitInitFailed(detail)
            }
            throw StoreError.gitInitFailed("exit \(process.terminationStatus)")
        }
    }

    /// `git clone <remoteURL> <mainDir>` — `mainDir` already exists (empty) from layout ensure.
    private func gitClone(remoteURL: String, into mainDir: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["clone", remoteURL, mainDir.path]
        let stderr = Pipe()
        process.standardOutput = Pipe()
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw StoreError.gitCloneFailed(error.localizedDescription)
        }

        guard process.terminationStatus == 0 else {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let detail, !detail.isEmpty {
                throw StoreError.gitCloneFailed(detail)
            }
            throw StoreError.gitCloneFailed("exit \(process.terminationStatus)")
        }
    }

    private func scanPrefixDirectory(
        _ parent: URL,
        storedPrefix: String?,
        into byPath: inout [String: WorkspaceSummary]
    ) throws {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: parent.path, isDirectory: &isDir), isDir.boolValue else {
            return
        }

        let contents = try fileManager.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for child in contents {
            var childIsDir: ObjCBool = false
            guard fileManager.fileExists(atPath: child.path, isDirectory: &childIsDir),
                  childIsDir.boolValue
            else { continue }

            let configURL = SymphoniaPaths.workspaceConfigFile(in: child)
            guard fileManager.fileExists(atPath: configURL.path) else { continue }

            if let summary = try? summary(for: child, fallbackSlug: child.lastPathComponent, fallbackPrefix: storedPrefix) {
                byPath[summary.dataDirURL.path] = summary
            }
        }
    }

    private func summary(
        for dataDir: URL,
        fallbackSlug: String,
        fallbackPrefix: String?
    ) throws -> WorkspaceSummary {
        let config = (try? loadConfig(from: dataDir))
        let slug = config?.slug ?? fallbackSlug
        let prefix = config?.prefix ?? fallbackPrefix
        let mainDir = SymphoniaPaths.workspaceMainDirectory(in: dataDir)
        let isRepo = isGitRepository(mainDir)
        return WorkspaceSummary(
            slug: slug,
            prefix: prefix,
            dataDirURL: dataDir.standardizedFileURL,
            mainIsGitRepo: isRepo,
            mainHasCommits: isRepo && mainHasCommits(at: mainDir)
        )
    }

    /// Fast path: unborn HEAD has a symbolic ref whose tip file does not exist yet.
    private func mainHasCommits(at mainDir: URL) -> Bool {
        let gitURL = mainDir.appendingPathComponent(".git")
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: gitURL.path, isDirectory: &isDir) else { return false }

        // Linked worktree `.git` file — treat as having commits if the checkout exists as a repo.
        // Main is always a real git directory.
        guard isDir.boolValue else { return true }

        let headURL = gitURL.appendingPathComponent("HEAD")
        guard let head = try? String(contentsOf: headURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !head.isEmpty
        else { return false }

        if head.hasPrefix("ref:") {
            let ref = head.dropFirst(4).trimmingCharacters(in: .whitespacesAndNewlines)
            let refURL = gitURL.appendingPathComponent(ref)
            return fileManager.fileExists(atPath: refURL.path)
        }

        // Detached HEAD — a raw SHA means at least one commit exists.
        return head.count >= 7
    }

    private func loadIndex() -> WorkspaceIndexDocument {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return .empty
        }
        do {
            let text = try String(contentsOf: indexURL, encoding: .utf8)
            return try PreferencesToml.decodeWorkspaceIndex(from: text)
        } catch {
            return .empty
        }
    }

    private func writeIndex(_ index: WorkspaceIndexDocument) throws {
        let directory = indexURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let text = PreferencesToml.encode(index)
        try text.write(to: indexURL, atomically: true, encoding: .utf8)
    }

    private func registerInIndex(slug: String, prefix: String?) throws {
        var index = loadIndex()
        if let existing = index.entries.firstIndex(where: { $0.slug == slug && $0.prefix == prefix }) {
            index.entries[existing] = .init(slug: slug, prefix: prefix)
        } else if let sameSlug = index.entries.firstIndex(where: { $0.slug == slug }) {
            // Update prefix if Operator re-registered the same slug under a new parent.
            index.entries[sameSlug] = .init(slug: slug, prefix: prefix)
        } else {
            index.entries.append(.init(slug: slug, prefix: prefix))
        }
        try writeIndex(index)
    }

    private func updateIndexAfterRename(
        from summary: WorkspaceSummary,
        newSlug: String,
        prefix: String?,
        workspacesRoot: String
    ) throws {
        var index = loadIndex()
        let oldPath = summary.dataDirURL.standardizedFileURL.path

        index.entries.removeAll { entry in
            if entry.slug == summary.slug, entry.prefix == summary.prefix {
                return true
            }
            let entryDir = dataDirURL(
                slug: entry.slug,
                prefix: entry.prefix,
                workspacesRoot: workspacesRoot
            )
            return entryDir.standardizedFileURL.path == oldPath
        }

        index.entries.append(.init(slug: newSlug, prefix: prefix))

        if index.lastSelectedSlug == summary.slug {
            index.lastSelectedSlug = newSlug
        }

        try writeIndex(index)
    }

    private func unregisterFromIndex(matching summary: WorkspaceSummary, workspacesRoot: String) throws {
        var index = loadIndex()
        let targetPath = summary.dataDirURL.standardizedFileURL.path
        index.entries.removeAll { entry in
            if entry.slug == summary.slug, entry.prefix == summary.prefix {
                return true
            }
            let entryDir = dataDirURL(
                slug: entry.slug,
                prefix: entry.prefix,
                workspacesRoot: workspacesRoot
            )
            return entryDir.standardizedFileURL.path == targetPath
        }
        if index.lastSelectedSlug == summary.slug {
            index.lastSelectedSlug = nil
        }
        try writeIndex(index)
    }
}

import Foundation

/// On-disk Workspace Data Dir create / layout / list (ADR 0012, 0014, 0015).
///
/// Create runs `git init` in `main/` by default so dogfooding works immediately, or
/// `git clone <url>` when a Clone URL is supplied (P1.4) — the remote URL is then persisted
/// on `config.json` (`mainRemoteURL`) for future heal-on-open (P1.5). Clone-later: Operator
/// may also replace `main/` with a CLI clone into that same path. Opening an externally
/// prepared `main/` is supported — layout ensure does not touch an existing repo.
struct WorkspaceStore: Sendable {
    enum StoreError: LocalizedError, Equatable {
        case invalidSlug(String)
        case alreadyExists(URL)
        case missingConfig(URL)
        case notAWorkspace(URL)
        case gitInitFailed(String)
        case gitCloneFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidSlug(let message):
                return message
            case .alreadyExists(let url):
                return "Workspace Data Dir already exists: \(url.path)"
            case .missingConfig(let url):
                return "Missing config.json at \(url.path)"
            case .notAWorkspace(let url):
                return "Not a Workspace Data Dir: \(url.path)"
            case .gitInitFailed(let detail):
                return "git init failed: \(detail)"
            case .gitCloneFailed(let detail):
                return "git clone failed: \(detail)"
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
    /// remote URL is persisted on `config.json` (`mainRemoteURL`) for future heal-on-open
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

    /// Ensure `config.json`, `secrets.json` (0600), `main/`, `worktrees/` exist.
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
        let worktreesDir = SymphoniaPaths.workspaceWorktreesDirectory(in: dataDir)
        try fileManager.createDirectory(at: mainDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: worktreesDir, withIntermediateDirectories: true)

        if !isGitRepository(mainDir) {
            if let cloneRemoteURL {
                try gitClone(remoteURL: cloneRemoteURL, into: mainDir)
            } else if initializeMainRepo {
                try gitInit(at: mainDir)
            }
        }
    }

    /// Open an existing Workspace Data Dir (CLI-prepared `main/` is fine).
    func open(at dataDir: URL) throws -> WorkspaceSummary {
        let configURL = SymphoniaPaths.workspaceConfigFile(in: dataDir)
        guard fileManager.fileExists(atPath: configURL.path) else {
            throw StoreError.missingConfig(configURL)
        }

        // Do not re-init main/ — Operator may have cloned externally.
        try ensureLayout(at: dataDir, initializeMainRepo: false)
        let config = try loadConfig(from: dataDir)
        try registerInIndex(slug: config.slug, prefix: config.prefix)
        return try summary(for: dataDir, fallbackSlug: config.slug, fallbackPrefix: config.prefix)
    }

    // MARK: - Config I/O

    func loadConfig(from dataDir: URL) throws -> WorkspaceConfig {
        let url = SymphoniaPaths.workspaceConfigFile(in: dataDir)
        guard fileManager.fileExists(atPath: url.path) else {
            throw StoreError.missingConfig(url)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(WorkspaceConfig.self, from: data)
    }

    func writeConfig(_ config: WorkspaceConfig, to dataDir: URL) throws {
        try fileManager.createDirectory(at: dataDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: SymphoniaPaths.workspaceConfigFile(in: dataDir), options: .atomic)
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
            throw StoreError.gitInitFailed(detail?.isEmpty == false ? detail! : "exit \(process.terminationStatus)")
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
            throw StoreError.gitCloneFailed(detail?.isEmpty == false ? detail! : "exit \(process.terminationStatus)")
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
        return WorkspaceSummary(
            slug: slug,
            prefix: prefix,
            dataDirURL: dataDir.standardizedFileURL,
            mainIsGitRepo: isGitRepository(mainDir)
        )
    }

    private struct WorkspaceIndex: Codable, Equatable {
        struct Entry: Codable, Equatable {
            var slug: String
            var prefix: String?
        }

        var lastSelectedSlug: String?
        var entries: [Entry]

        static let empty = WorkspaceIndex(lastSelectedSlug: nil, entries: [])
    }

    private func loadIndex() -> WorkspaceIndex {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return .empty
        }
        do {
            let data = try Data(contentsOf: indexURL)
            return try JSONDecoder().decode(WorkspaceIndex.self, from: data)
        } catch {
            return .empty
        }
    }

    private func writeIndex(_ index: WorkspaceIndex) throws {
        let directory = indexURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(index)
        try data.write(to: indexURL, options: .atomic)
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
}

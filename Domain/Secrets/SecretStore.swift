import Foundation

/// Persist / load Workspace Secret Store under the Workspace Data Dir (ADR 0001, 0012, T.3).
///
/// Canonical file: `<data-dir>/secrets.toml` (mode 0600). Never written into `main/` or a
/// Worktree checkout — both are git repos/checkouts that sit as siblings under the Workspace
/// Data Dir (ADR 0014, P1.5); the Workspace Data Dir itself never is.
/// Legacy `secrets.json` / non-empty `secrets.env` are ignored (no migration).
struct SecretStore: @unchecked Sendable {
    enum StoreError: LocalizedError, Equatable {
        case missingWorkspace
        case invalidKey(String)
        case writeFailed(String)
        case readFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingWorkspace:
                return "No Workspace selected."
            case .invalidKey(let key):
                return "Invalid Env Var key “\(key)”. Use letters, digits, and underscore; must start with a letter or underscore."
            case .writeFailed(let detail):
                return "Failed to write Secret Store: \(detail)"
            case .readFailed(let detail):
                return "Failed to read Secret Store: \(detail)"
            }
        }
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Ensure `secrets.toml` exists with mode 0600. Removes empty legacy `secrets.env` only.
    func ensureStoreFile(in dataDir: URL) throws {
        let tomlURL = SymphoniaPaths.workspaceSecretsFile(in: dataDir)
        if !fileManager.fileExists(atPath: tomlURL.path) {
            try write(SecretStoreDocument.empty, to: dataDir)
        } else {
            try applyTightPermissions(at: tomlURL)
        }

        // Legacy placeholder from Phase 3 — remove only if empty so we do not destroy Operator data.
        let legacyURL = SymphoniaPaths.workspaceSecretsEnvFile(in: dataDir)
        if fileManager.fileExists(atPath: legacyURL.path) {
            let attrs = try? fileManager.attributesOfItem(atPath: legacyURL.path)
            let size = (attrs?[.size] as? NSNumber)?.intValue ?? -1
            if size == 0 {
                try? fileManager.removeItem(at: legacyURL)
            } else {
                // Non-empty legacy file: keep it but do not auto-import; Secret Store uses TOML only.
                try? applyTightPermissions(at: legacyURL)
            }
        }
    }

    func load(from dataDir: URL) throws -> SecretStoreDocument {
        try ensureStoreFile(in: dataDir)
        let url = SymphoniaPaths.workspaceSecretsFile(in: dataDir)
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .empty
            }
            var document = try PreferencesToml.decodeSecretStore(from: text)
            if document.version < SecretStoreDocument.currentVersion {
                document.version = SecretStoreDocument.currentVersion
            }
            return document
        } catch let error as PreferencesTomlError {
            throw StoreError.readFailed(error.localizedDescription)
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.readFailed(error.localizedDescription)
        }
    }

    func write(_ document: SecretStoreDocument, to dataDir: URL) throws {
        // P5.5 / P1.5: `dataDir` must be the Workspace Data Dir itself — never `main/` or a
        // sibling Worktree checkout. Both are git repos; the Workspace Data Dir never is, so
        // this generalizes to the flat P1.5 layout without hardcoding a `worktrees/` prefix.
        precondition(
            !isGitRepository(dataDir),
            "Secret Store must not write into main/ or a Worktree checkout"
        )

        try fileManager.createDirectory(at: dataDir, withIntermediateDirectories: true)

        var toWrite = document
        toWrite.version = SecretStoreDocument.currentVersion

        let text = PreferencesToml.encode(toWrite)
        guard let data = text.data(using: .utf8) else {
            throw StoreError.writeFailed("UTF-8 encode failed")
        }

        let url = SymphoniaPaths.workspaceSecretsFile(in: dataDir)
        let tempURL = url.appendingPathExtension("tmp")
        do {
            try data.write(to: tempURL, options: .atomic)
            try applyTightPermissions(at: tempURL)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            try fileManager.moveItem(at: tempURL, to: url)
            try applyTightPermissions(at: url)
        } catch let error as StoreError {
            try? fileManager.removeItem(at: tempURL)
            throw error
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw StoreError.writeFailed(error.localizedDescription)
        }
    }

    /// Validate a shell-style Env Var key.
    static func validateKey(_ raw: String) -> Result<String, StoreError> {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            return .failure(.invalidKey(raw))
        }
        // POSIX-ish: [A-Za-z_][A-Za-z0-9_]*
        let pattern = #"^[A-Za-z_][A-Za-z0-9_]*$"#
        guard key.range(of: pattern, options: .regularExpression) != nil else {
            return .failure(.invalidKey(key))
        }
        return .success(key)
    }

    private func isGitRepository(_ dir: URL) -> Bool {
        fileManager.fileExists(atPath: dir.appendingPathComponent(".git").path)
    }

    private func applyTightPermissions(at url: URL) throws {
        do {
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            throw StoreError.writeFailed("chmod 0600: \(error.localizedDescription)")
        }
    }
}

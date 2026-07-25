import Foundation

/// On-disk layout under `~/.symphonia` (ADR 0012, 0015).
enum SymphoniaPaths {
    /// App data root: `~/.symphonia`.
    static var homeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".symphonia", isDirectory: true)
    }

    /// Global preferences file: `~/.symphonia/preferences.toml` (T.1).
    /// Legacy `preferences.json` is ignored (no migration).
    static var preferencesFile: URL {
        homeDirectory.appendingPathComponent("preferences.toml", isDirectory: false)
    }

    /// Default Workspaces Root: `~/.symphonia/workspaces` (ADR 0015).
    static var defaultWorkspacesRoot: URL {
        homeDirectory.appendingPathComponent("workspaces", isDirectory: true)
    }

    /// Index of known Workspace slugs / Prefixes + last selection: `~/.symphonia/workspace-index.json`.
    static var workspaceIndexFile: URL {
        homeDirectory.appendingPathComponent("workspace-index.json", isDirectory: false)
    }

    /// Workspace Data Dir: `<prefix>/<slug>/` (ADR 0015).
    static func workspaceDataDirectory(prefix: URL, slug: String) -> URL {
        prefix.appendingPathComponent(slug, isDirectory: true)
    }

    /// Workspace config: `<data-dir>/config.json`.
    static func workspaceConfigFile(in dataDir: URL) -> URL {
        dataDir.appendingPathComponent("config.json", isDirectory: false)
    }

    /// Secret Store (canonical): `<data-dir>/secrets.json` (mode 0600; ADR 0001, 0012).
    static func workspaceSecretsJSONFile(in dataDir: URL) -> URL {
        dataDir.appendingPathComponent("secrets.json", isDirectory: false)
    }

    /// Legacy Phase 3 placeholder: `<data-dir>/secrets.env` (migrated away when empty).
    static func workspaceSecretsEnvFile(in dataDir: URL) -> URL {
        dataDir.appendingPathComponent("secrets.env", isDirectory: false)
    }

    /// Alias for callers that still say “secrets file” — points at `secrets.json`.
    static func workspaceSecretsFile(in dataDir: URL) -> URL {
        workspaceSecretsJSONFile(in: dataDir)
    }

    /// Main Repo directory: `<data-dir>/main/` — protected; never removable/archivable, and
    /// healed (re-clone or `git init`) on open if missing or not a git repo (ADR 0014, P1.5).
    static func workspaceMainDirectory(in dataDir: URL) -> URL {
        dataDir.appendingPathComponent("main", isDirectory: true)
    }

    /// Reserved top-level names directly under a Workspace Data Dir that a Worktree folder can
    /// never take — case-insensitive (ADR 0014, P1.5). Currently just `main`, the protected Main
    /// Repo directory. `WorkspaceSlug.validate` folds this set into its own reserved-name check
    /// (reused by `AgentController.createAgent()` for Operator-edited Worktree folder names), and
    /// `AgentStore` re-checks it directly so the guard holds even when the domain layer is called
    /// without going through that validator.
    static let reservedWorkspaceChildNames: Set<String> = ["main"]

    /// One Worktree checkout — a **sibling of `main/`**: `<data-dir>/<three-word-name>/`. No
    /// `worktrees/` parent (ADR 0014 flattened in P1.5; folder-naming rules from ADR 0017, 0018
    /// still apply).
    static func workspaceWorktreeDirectory(in dataDir: URL, threeWordName: String) -> URL {
        dataDir.appendingPathComponent(threeWordName, isDirectory: true)
    }

    /// Expand `~` / `$HOME` prefixes to an absolute file URL.
    static func expandingTildeInPath(_ path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }
}

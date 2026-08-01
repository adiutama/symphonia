import Foundation

/// On-disk layout under `~/.symphonia` (ADR 2026-07-23-0012-workspace-data-dir-plaintext / 2026-07-23-0015-workspace-prefix-self-contained).
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

    /// Default Workspaces Root: `~/.symphonia/workspaces` (ADR 2026-07-23-0015-workspace-prefix-self-contained).
    static var defaultWorkspacesRoot: URL {
        homeDirectory.appendingPathComponent("workspaces", isDirectory: true)
    }

    /// Index of known Workspace slugs / Prefixes + last selection: `~/.symphonia/workspace-index.toml` (T.3).
    /// Legacy `workspace-index.json` is ignored (no migration).
    static var workspaceIndexFile: URL {
        homeDirectory.appendingPathComponent("workspace-index.toml", isDirectory: false)
    }

    /// Workspace Data Dir: `<prefix>/<slug>/` (ADR 2026-07-23-0015-workspace-prefix-self-contained).
    static func workspaceDataDirectory(prefix: URL, slug: String) -> URL {
        prefix.appendingPathComponent(slug, isDirectory: true)
    }

    /// Workspace config: `<data-dir>/config.toml` (T.2). Legacy `config.json` ignored.
    static func workspaceConfigFile(in dataDir: URL) -> URL {
        dataDir.appendingPathComponent("config.toml", isDirectory: false)
    }

    /// Secret Store (canonical): `<data-dir>/secrets.toml` (mode 0600; ADR 2026-07-23-0001-workspace-secret-store / 2026-07-23-0012-workspace-data-dir-plaintext, T.3).
    /// Legacy `secrets.json` is ignored (no migration).
    static func workspaceSecretsFile(in dataDir: URL) -> URL {
        dataDir.appendingPathComponent("secrets.toml", isDirectory: false)
    }

    /// Legacy Phase 5 JSON path — ignored; kept for reserved-name / docs clarity only.
    static func workspaceSecretsJSONFile(in dataDir: URL) -> URL {
        dataDir.appendingPathComponent("secrets.json", isDirectory: false)
    }

    /// Legacy Phase 3 placeholder: `<data-dir>/secrets.env` (removed when empty; never imported).
    static func workspaceSecretsEnvFile(in dataDir: URL) -> URL {
        dataDir.appendingPathComponent("secrets.env", isDirectory: false)
    }

    /// Main Repo directory: `<data-dir>/main/` — protected; never removable/archivable, and
    /// healed (re-clone or `git init`) on open if missing or not a git repo (ADR 2026-07-23-0014-main-repo-dir-and-external-clone, P1.5).
    static func workspaceMainDirectory(in dataDir: URL) -> URL {
        dataDir.appendingPathComponent("main", isDirectory: true)
    }

    /// Reserved top-level names directly under a Workspace Data Dir that a Worktree folder can
    /// never take — case-insensitive (ADR 2026-07-23-0014-main-repo-dir-and-external-clone, P1.5). Currently just `main`, the protected Main
    /// Repo directory. `WorkspaceSlug.validate` folds this set into its own reserved-name check
    /// (reused by `WorktreeController.createWorktree()` for Operator-edited Worktree folder names), and
    /// `WorktreeStore` re-checks it directly so the guard holds even when the domain layer is called
    /// without going through that validator.
    static let reservedWorkspaceChildNames: Set<String> = ["main"]

    /// One Worktree checkout — a **sibling of `main/`**: `<data-dir>/<three-word-name>/`. No
    /// `worktrees/` parent (ADR 2026-07-23-0014-main-repo-dir-and-external-clone flattened in P1.5; folder-naming rules from ADR 2026-07-23-0017-agent-branch-three-word-auto / 2026-07-23-0018-agent-folder-auto-branch-independent
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

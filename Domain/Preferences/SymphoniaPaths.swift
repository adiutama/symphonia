import Foundation

/// On-disk layout under `~/.symphonia` (ADR 0012, 0015).
enum SymphoniaPaths {
    /// App data root: `~/.symphonia`.
    static var homeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".symphonia", isDirectory: true)
    }

    /// Global preferences file: `~/.symphonia/preferences.json` (ADR 0012).
    static var preferencesFile: URL {
        homeDirectory.appendingPathComponent("preferences.json", isDirectory: false)
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

    /// Main Repo directory: `<data-dir>/main/` (ADR 0014).
    static func workspaceMainDirectory(in dataDir: URL) -> URL {
        dataDir.appendingPathComponent("main", isDirectory: true)
    }

    /// Agent Worktrees parent: `<data-dir>/worktrees/` (ADR 0003, 0012).
    static func workspaceWorktreesDirectory(in dataDir: URL) -> URL {
        dataDir.appendingPathComponent("worktrees", isDirectory: true)
    }

    /// One Agent Worktree: `<data-dir>/worktrees/<three-word-name>/` (ADR 0017, 0018).
    static func agentWorktreeDirectory(in dataDir: URL, threeWordName: String) -> URL {
        workspaceWorktreesDirectory(in: dataDir)
            .appendingPathComponent(threeWordName, isDirectory: true)
    }

    /// Expand `~` / `$HOME` prefixes to an absolute file URL.
    static func expandingTildeInPath(_ path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }
}

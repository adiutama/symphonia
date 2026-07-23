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

    /// Secret Store placeholder: `<data-dir>/secrets.env` (mode 0600; Phase 5 fills real store).
    static func workspaceSecretsFile(in dataDir: URL) -> URL {
        dataDir.appendingPathComponent("secrets.env", isDirectory: false)
    }

    /// Main Repo directory: `<data-dir>/main/` (ADR 0014).
    static func workspaceMainDirectory(in dataDir: URL) -> URL {
        dataDir.appendingPathComponent("main", isDirectory: true)
    }

    /// Agent Worktrees parent: `<data-dir>/worktrees/` (empty until Phase 4).
    static func workspaceWorktreesDirectory(in dataDir: URL) -> URL {
        dataDir.appendingPathComponent("worktrees", isDirectory: true)
    }

    /// Expand `~` / `$HOME` prefixes to an absolute file URL.
    static func expandingTildeInPath(_ path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }
}

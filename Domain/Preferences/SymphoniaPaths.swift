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

    /// Expand `~` / `$HOME` prefixes to an absolute file URL.
    static func expandingTildeInPath(_ path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }
}

import Foundation

/// Focusable terminal session: Main Repo or a Worktree.
///
/// Owns Main CLI cwd / spawn env and scopes Overlay PTYs (Editor + Background).
enum FocusedSession: Equatable, Identifiable, Sendable {
    /// Main Repo at `<workspace>/main/` — same Editor / Background / secrets treatment as a Worktree.
    case mainRepo(workspaceId: String, mainDirectory: URL, slug: String)
    /// Worktree — a sibling of `main/` under `<workspace>/<three-word>/` (P1.5).
    case worktree(WorktreeSummary)

    var id: String {
        switch self {
        case .mainRepo(let workspaceId, _, _):
            return "main:\(workspaceId)"
        case .worktree(let wt):
            return "worktree:\(wt.id)"
        }
    }

    /// Ghostty cwd for Main CLI and Overlay spawn.
    var workingDirectory: String {
        switch self {
        case .mainRepo(_, let mainDirectory, _):
            return mainDirectory.path
        case .worktree(let wt):
            return wt.worktreeURL.path
        }
    }

    var isMainRepo: Bool {
        if case .mainRepo = self { return true }
        return false
    }

    var worktree: WorktreeSummary? {
        if case .worktree(let wt) = self { return wt }
        return nil
    }

    static func mainRepo(for workspace: WorkspaceSummary) -> FocusedSession {
        .mainRepo(
            workspaceId: workspace.id,
            mainDirectory: SymphoniaPaths.workspaceMainDirectory(in: workspace.dataDirURL),
            slug: workspace.slug
        )
    }

    /// Remap a session id when a Workspace Data Dir moves (rename / Prefix relocate).
    static func remappedID(_ sessionId: String, fromOldDataDir oldPath: String, toNewDataDir newPath: String) -> String {
        guard oldPath != newPath else { return sessionId }
        if sessionId == "main:\(oldPath)" {
            return "main:\(newPath)"
        }
        let prefix = "worktree:"
        guard sessionId.hasPrefix(prefix) else { return sessionId }
        let path = String(sessionId.dropFirst(prefix.count))
        guard path == oldPath || path.hasPrefix(oldPath + "/") else { return sessionId }
        return prefix + newPath + path.dropFirst(oldPath.count)
    }

    /// Remap an absolute path under a relocated Workspace Data Dir.
    static func remappedPath(_ path: String, fromOldDataDir oldPath: String, toNewDataDir newPath: String) -> String {
        guard oldPath != newPath else { return path }
        guard path == oldPath || path.hasPrefix(oldPath + "/") else { return path }
        return newPath + path.dropFirst(oldPath.count)
    }
}

extension WorktreeSummary {
    /// Branch name primary; Three-Word folder as fallback when branch unknown.
    var primaryLabel: String {
        let branch = branchName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return branch.isEmpty ? threeWordName : branch
    }

    /// Subtle secondary line — folder name when branch is shown as primary.
    var secondaryLabel: String? {
        let branch = branchName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !branch.isEmpty, branch != threeWordName else { return nil }
        return threeWordName
    }
}

/// Lowercases sidebar list chrome only (Workspace slugs, branch/folder labels) — a calm, dense
/// map of work. Never mutates the underlying git branch / folder names used for operations.
func displayLowercased(_ value: String) -> String {
    value.lowercased()
}

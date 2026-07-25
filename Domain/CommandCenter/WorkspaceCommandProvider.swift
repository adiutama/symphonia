import Foundation

/// Exports Workspace / Worktree Commands into the `CommandRegistry` (ADR 0021 §2).
///
/// Matches today's hardcoded Command Mode root items for switching Workspaces and
/// focusing Worktrees (`CommandModeController.rootItems()`). Subtitles are computed live
/// from the injected controllers each time `commands` is read, so they track current
/// selection the same way the old private root list did.
struct WorkspaceCommandProvider: CommandProvider {
    let workspaces: WorkspaceController
    let worktrees: WorktreeController

    var commands: [Command] {
        let focusedTargetSubtitle: String = {
            guard let session = worktrees.focusedSession else { return "none focused" }
            switch session {
            case .mainRepo(_, _, let slug):
                return "main · \(slug)"
            case .worktree(let wt):
                return wt.primaryLabel
            }
        }()

        return [
            Command(
                id: "workspace.switch",
                title: "Switch Workspace…",
                subtitle: workspaces.current.map { "current: \($0.slug)" } ?? "none selected",
                group: "Workspace",
                defaultAliases: ["/workspace", "/w"],
                defaultShortcut: "ctrl+w",
                action: .showWorkspacePicker
            ),
            Command(
                id: "workspace.rename",
                title: "Rename Workspace…",
                subtitle: workspaces.current.map(\.slug) ?? "needs Workspace",
                group: "Workspace",
                defaultAliases: ["/renameworkspace"],
                defaultShortcut: nil,
                action: .renameWorkspace,
                isEnabled: { _ in workspaces.current != nil }
            ),
            Command(
                id: "worktree.focusPicker",
                title: "Focus Worktree…",
                subtitle: focusedTargetSubtitle,
                group: "Worktree",
                defaultAliases: ["/focus"],
                defaultShortcut: "ctrl+a",
                action: .showWorktreePicker
            ),
            Command(
                id: "worktree.focusMain",
                title: "Focus Main…",
                subtitle: workspaces.current.map(\.slug) ?? "needs Workspace",
                group: "Worktree",
                defaultAliases: ["/main"],
                defaultShortcut: "ctrl+m",
                action: .focusMainRepo
            ),
            Command(
                id: "worktree.renameFocused",
                title: "Rename Worktree…",
                subtitle: worktrees.focused.map(\.primaryLabel) ?? "needs focused Worktree",
                group: "Worktree",
                defaultAliases: ["/renameworktree"],
                defaultShortcut: "ctrl+r",
                action: .renameFocusedWorktree,
                isEnabled: { _ in worktrees.focused != nil }
            ),
            Command(
                id: "worktree.reloadCLI",
                title: "Reload CLI",
                subtitle: focusedTargetSubtitle,
                group: "Worktree",
                defaultAliases: ["/reload"],
                defaultShortcut: "ctrl+l",
                action: .reloadFocusedCLI,
                isEnabled: { $0.hasFocusedSession }
            ),
            Command(
                id: "worktree.new",
                title: "New Worktree",
                subtitle: workspaces.current == nil ? "needs Workspace" : "opens create sheet",
                group: "Worktree",
                defaultAliases: ["/new"],
                defaultShortcut: "ctrl+n",
                action: .newWorktree
            ),
            Command(
                id: "worktree.removeFocused",
                title: "Remove Worktree…",
                subtitle: worktrees.focused.map(\.primaryLabel) ?? "needs focused Worktree",
                group: "Worktree",
                defaultAliases: ["/remove"],
                defaultShortcut: "ctrl+x",
                action: .removeFocusedWorktree
            ),
            Command(
                id: "workspace.remove",
                title: "Remove Workspace…",
                subtitle: workspaces.current.map { "delete \u{201C}\($0.slug)\u{201D} from disk" } ?? "needs Workspace",
                group: "Workspace",
                defaultAliases: ["/rmworkspace", "/rw"],
                defaultShortcut: nil,
                action: .removeCurrentWorkspace,
                isEnabled: { _ in workspaces.current != nil }
            ),
        ]
    }
}

/// Exports chrome-level Commands that don't belong to a specific app area (ADR 0021 §2)
/// — Settings and dismissing Command Center itself. No context gating: both are always
/// available while Command Center is open.
struct ChromeCommandProvider: CommandProvider {
    var commands: [Command] {
        [
            Command(
                id: "chrome.openSettings",
                title: "Open Settings…",
                subtitle: "Opens the Settings window",
                group: "App",
                defaultAliases: ["/settings"],
                defaultShortcut: "ctrl+,",
                action: .openSettings
            ),
            Command(
                id: "chrome.toggleStatusCue",
                title: "Toggle Status Cue",
                subtitle: "Show or hide the calm Overlay info list",
                group: "View",
                defaultAliases: ["/cue", "/status"],
                defaultShortcut: nil,
                action: .toggleStatusCue
            ),
            Command(
                id: "chrome.dismiss",
                title: "Dismiss Command Center",
                subtitle: "Esc",
                group: "App",
                action: .dismiss
            ),
        ]
    }
}

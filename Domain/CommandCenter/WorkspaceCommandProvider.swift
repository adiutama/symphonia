import Foundation

/// Exports Workspace / Worktree Commands into the `CommandRegistry` (ADR 0021 §2 / Path B).
///
/// Titles are the keymap — distinct verbs/nouns so default sequences do not collide.
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
                title: "Switch Workspace",
                subtitle: workspaces.current.map { "current: \($0.slug)" } ?? "none selected",
                group: "Workspace",
                defaultAliases: ["/workspace", "/w"],
                action: .showWorkspacePicker
            ),
            Command(
                id: "workspace.rename",
                title: "Rename Slug",
                subtitle: workspaces.current.map(\.slug) ?? "needs Workspace",
                group: "Workspace",
                defaultAliases: ["/renameworkspace", "Rename Workspace"],
                action: .renameWorkspace,
                isEnabled: { _ in workspaces.current != nil }
            ),
            Command(
                id: "worktree.focusPicker",
                title: "Focus Worktree",
                subtitle: focusedTargetSubtitle,
                group: "Worktree",
                defaultAliases: ["/focus"],
                action: .showWorktreePicker
            ),
            Command(
                id: "worktree.focusMain",
                title: "Focus Main",
                subtitle: workspaces.current.map(\.slug) ?? "needs Workspace",
                group: "Worktree",
                defaultAliases: ["/main"],
                action: .focusMainRepo
            ),
            Command(
                id: "worktree.renameFocused",
                title: "Rename Tree",
                subtitle: worktrees.focused.map(\.primaryLabel) ?? "needs focused Worktree",
                group: "Worktree",
                defaultAliases: ["/renameworktree", "Rename Worktree"],
                action: .renameFocusedWorktree,
                isEnabled: { _ in worktrees.focused != nil }
            ),
            Command(
                id: "worktree.reloadCLI",
                title: "Reload CLI",
                subtitle: focusedTargetSubtitle,
                group: "Worktree",
                defaultAliases: ["/reload"],
                action: .reloadFocusedCLI,
                isEnabled: { $0.hasFocusedSession }
            ),
            Command(
                id: "worktree.new",
                title: "New Worktree",
                subtitle: workspaces.current == nil ? "needs Workspace" : "opens create sheet",
                group: "Worktree",
                defaultAliases: ["/new"],
                action: .newWorktree
            ),
            Command(
                id: "worktree.removeFocused",
                title: "Discard Tree",
                subtitle: worktrees.focused.map(\.primaryLabel) ?? "needs focused Worktree",
                group: "Worktree",
                defaultAliases: ["/remove", "Remove Worktree"],
                action: .removeFocusedWorktree
            ),
            Command(
                id: "workspace.remove",
                title: "Discard Workspace",
                subtitle: workspaces.current.map { "delete \u{201C}\($0.slug)\u{201D} from disk" } ?? "needs Workspace",
                group: "Workspace",
                defaultAliases: ["/rmworkspace", "/rw", "Remove Workspace"],
                action: .removeCurrentWorkspace,
                isEnabled: { _ in workspaces.current != nil }
            ),
        ]
    }
}

/// Exports chrome-level Commands that don't belong to a specific app area (ADR 0021 §2).
struct ChromeCommandProvider: CommandProvider {
    var commands: [Command] {
        [
            Command(
                id: "chrome.openSettings",
                title: "Settings",
                subtitle: "Opens the Settings window",
                group: "App",
                defaultAliases: ["/settings", "Open Settings"],
                action: .openSettings
            ),
            Command(
                id: "chrome.toggleStatusCue",
                title: "Status Cue",
                subtitle: "Show or hide the calm Overlay info list",
                group: "View",
                defaultAliases: ["/cue", "/status", "Toggle Status Cue"],
                action: .toggleStatusCue
            ),
            Command(
                id: "chrome.dismiss",
                title: "Dismiss",
                subtitle: "Esc",
                group: "App",
                defaultAliases: ["Dismiss Command Center"],
                action: .dismiss
            ),
        ]
    }
}

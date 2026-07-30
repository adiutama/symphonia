import Foundation

/// Exports Workspace / Worktree Commands into the `CommandRegistry` (ADR 0021 §2 / ADR 0022).
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
                defaultSequence: "ww",
                action: .showWorkspacePicker
            ),
            Command(
                id: "workspace.new",
                title: "New Workspace",
                subtitle: "opens create sheet",
                group: "Workspace",
                defaultSequence: "wn",
                action: .newWorkspace
            ),
            Command(
                id: "workspace.cycleNext",
                title: "Next Workspace",
                subtitle: workspaces.current.map(\.slug) ?? "none selected",
                group: "Workspace",
                defaultSequence: "",
                action: .cycleNextWorkspace,
                isEnabled: { _ in !workspaces.workspaces.isEmpty }
            ),
            Command(
                id: "workspace.cyclePrev",
                title: "Previous Workspace",
                subtitle: workspaces.current.map(\.slug) ?? "none selected",
                group: "Workspace",
                defaultSequence: "",
                action: .cyclePrevWorkspace,
                isEnabled: { _ in !workspaces.workspaces.isEmpty }
            ),
            Command(
                id: "workspace.rename",
                title: "Rename Workspace",
                subtitle: workspaces.current.map(\.slug) ?? "needs Workspace",
                group: "Workspace",
                defaultSequence: "wr",
                action: .renameWorkspace,
                isEnabled: { _ in workspaces.current != nil }
            ),
            Command(
                id: "workspace.remove",
                title: "Remove Workspace",
                subtitle: workspaces.current.map { "delete \u{201C}\($0.slug)\u{201D} from disk" } ?? "needs Workspace",
                group: "Workspace",
                defaultSequence: "wd",
                action: .removeCurrentWorkspace,
                isEnabled: { _ in workspaces.current != nil }
            ),
            Command(
                id: "worktree.focusPicker",
                title: "Switch Worktree",
                subtitle: focusedTargetSubtitle,
                group: "Worktree",
                defaultSequence: "tt",
                action: .showWorktreePicker
            ),
            Command(
                id: "worktree.cycleNext",
                title: "Next Worktree",
                subtitle: focusedTargetSubtitle,
                group: "Worktree",
                defaultSequence: "",
                action: .cycleNextWorktree,
                isEnabled: { _ in workspaces.current != nil }
            ),
            Command(
                id: "worktree.cyclePrev",
                title: "Previous Worktree",
                subtitle: focusedTargetSubtitle,
                group: "Worktree",
                defaultSequence: "",
                action: .cyclePrevWorktree,
                isEnabled: { _ in workspaces.current != nil }
            ),
            Command(
                id: "worktree.focusMain",
                title: "Focus Main",
                subtitle: workspaces.current.map(\.slug) ?? "needs Workspace",
                group: "Worktree",
                defaultSequence: "mm",
                action: .focusMainRepo,
                isEnabled: { _ in workspaces.current != nil }
            ),
            Command(
                id: "worktree.renameFocused",
                title: "Rename Worktree",
                subtitle: worktrees.focused.map(\.primaryLabel) ?? "needs focused Worktree",
                group: "Worktree",
                defaultSequence: "tr",
                action: .renameFocusedWorktree,
                isEnabled: { _ in worktrees.focused != nil }
            ),
            Command(
                id: "worktree.reloadCLI",
                title: "Reload CLI",
                subtitle: focusedTargetSubtitle,
                group: "Worktree",
                defaultSequence: "rr",
                action: .reloadFocusedCLI,
                isEnabled: { $0.hasFocusedSession }
            ),
            Command(
                id: "worktree.new",
                title: "New Worktree",
                subtitle: workspaces.current == nil ? "needs Workspace" : "opens create sheet",
                group: "Worktree",
                defaultSequence: "tn",
                action: .newWorktree
            ),
            Command(
                id: "worktree.removeFocused",
                title: "Remove Worktree",
                subtitle: worktrees.focused.map(\.primaryLabel) ?? "needs focused Worktree",
                group: "Worktree",
                defaultSequence: "td",
                action: .removeFocusedWorktree
            ),
        ]
    }
}

/// Exports chrome-level Commands that don't belong to a specific app area (ADR 0021 §2 / ADR 0022).
struct ChromeCommandProvider: CommandProvider {
    var commands: [Command] {
        [
            Command(
                id: "chrome.openSettings",
                title: "Settings",
                subtitle: "Opens the Settings window",
                group: "App",
                defaultSequence: "so",
                action: .openSettings
            ),
            Command(
                id: "chrome.openKeymap",
                title: "Keymap",
                subtitle: "Show keyboard shortcuts (⌘⇧/)",
                group: "App",
                defaultSequence: "kh",
                action: .openKeymap
            ),
            Command(
                id: "chrome.dismiss",
                title: "Dismiss",
                subtitle: "Esc",
                group: "App",
                defaultSequence: "",
                action: .dismiss
            ),
        ]
    }
}

import Foundation

/// Exports Workspace / Agent Commands into the `CommandRegistry` (ADR 0021 §2).
///
/// Matches today's hardcoded Command Mode root items for switching Workspaces and
/// focusing Worktrees (`CommandModeController.rootItems()`). Subtitles are computed live
/// from the injected controllers each time `commands` is read, so they track current
/// selection the same way the old private root list did.
struct WorkspaceCommandProvider: CommandProvider {
    let workspaces: WorkspaceController
    let agents: AgentController

    var commands: [Command] {
        let focusedTargetSubtitle: String = {
            guard let session = agents.focusedSession else { return "none focused" }
            switch session {
            case .mainRepo(_, _, let slug):
                return "main · \(slug)"
            case .agent(let agent):
                return agent.primaryLabel
            }
        }()

        return [
            Command(
                id: "workspace.switch",
                title: "Switch Workspace…",
                subtitle: workspaces.current.map { "current: \($0.slug)" } ?? "none selected",
                group: "Workspace",
                defaultAliases: ["/workspace", "/w"],
                defaultShortcut: "w",
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
                id: "agent.focusPicker",
                title: "Focus Worktree…",
                subtitle: focusedTargetSubtitle,
                group: "Worktree",
                defaultAliases: ["/focus"],
                defaultShortcut: "a",
                action: .showAgentPicker
            ),
            Command(
                id: "agent.focusMain",
                title: "Focus Main…",
                subtitle: workspaces.current.map(\.slug) ?? "needs Workspace",
                group: "Worktree",
                defaultAliases: ["/main"],
                defaultShortcut: "m",
                action: .focusMainRepo
            ),
            Command(
                id: "agent.renameFocused",
                title: "Rename Worktree…",
                subtitle: agents.focused.map(\.primaryLabel) ?? "needs focused Worktree",
                group: "Worktree",
                defaultAliases: ["/renameworktree"],
                defaultShortcut: "r",
                action: .renameFocusedWorktree,
                isEnabled: { _ in agents.focused != nil }
            ),
            Command(
                id: "agent.reloadCLI",
                title: "Reload CLI",
                subtitle: focusedTargetSubtitle,
                group: "Worktree",
                defaultAliases: ["/reload"],
                defaultShortcut: "l",
                action: .reloadFocusedCLI,
                isEnabled: { $0.hasFocusedSession }
            ),
            Command(
                id: "agent.new",
                title: "New Worktree",
                subtitle: workspaces.current == nil ? "needs Workspace" : nil,
                group: "Worktree",
                defaultAliases: ["/new"],
                defaultShortcut: "n",
                action: .newAgent
            ),
            Command(
                id: "agent.removeFocused",
                title: "Remove Worktree…",
                subtitle: agents.focused.map(\.primaryLabel) ?? "needs focused Worktree",
                group: "Worktree",
                defaultAliases: ["/remove"],
                defaultShortcut: "x",
                action: .removeFocusedAgent
            ),
            Command(
                id: "workspace.remove",
                title: "Remove Workspace…",
                subtitle: workspaces.current.map { "delete “\($0.slug)” from disk" } ?? "needs Workspace",
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
                subtitle: "Secret Store lives under Workspace",
                group: "Settings",
                defaultAliases: ["/settings"],
                defaultShortcut: ",",
                action: .openSettings
            ),
            Command(
                id: "chrome.dismiss",
                title: "Dismiss Command Center",
                subtitle: "Esc",
                group: "Settings",
                action: .dismiss
            ),
        ]
    }
}

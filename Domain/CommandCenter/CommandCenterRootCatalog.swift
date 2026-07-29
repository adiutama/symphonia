import Foundation

/// Builds Command Center root palette rows from the command registry (ADR 0021 / 0022).
///
/// Owned by `CommandCenterController`; nest pickers live in `CommandCenterNestCatalog`.
@MainActor
struct CommandCenterRootCatalog {
    let commandRegistry: CommandRegistry
    let preferences: PreferencesController
    let worktrees: WorktreeController
    let overlays: OverlayController

    func items(mode: CommandCenterMode, filterQuery: String) -> [CommandCenterItem] {
        let context = CommandContext(worktrees: worktrees, overlays: overlays)
        let commands = commandRegistry.availableCommands(context: context)
            .filter { command in
                switch command.action {
                case .dismiss,
                     .cycleNextWorkspace, .cyclePrevWorkspace,
                     .cycleNextWorktree, .cyclePrevWorktree:
                    return false
                default:
                    return true
                }
            }
        let overrides = preferences.preferences.commandBindings

        switch mode {
        case .input:
            let query = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let matched = query.isEmpty
                ? commands
                : commands.filter { matches($0, query: query, overrides: overrides) }
            return matched.map { commandItem($0, overrides: overrides) }

        case .normal:
            let mapped = commands.map { commandItem($0, overrides: overrides) }
            return CommandCenterItemFilter.filter(mapped, mode: .normal, query: filterQuery)
        }
    }

    private func matches(
        _ command: Command,
        query: String,
        overrides: [String: CommandBindingOverride]
    ) -> Bool {
        if command.title.lowercased().contains(query) { return true }
        if let subtitle = command.subtitle, subtitle.lowercased().contains(query) { return true }
        if let sequence = CommandBindingResolver.sequence(for: command, overrides: overrides) {
            return sequence.lowercased().contains(query)
        }
        return false
    }

    private func commandItem(
        _ command: Command,
        overrides: [String: CommandBindingOverride]
    ) -> CommandCenterItem {
        CommandCenterItem(
            id: command.id,
            title: command.title,
            subtitle: liveSubtitle(for: command),
            sequence: CommandBindingResolver.sequence(for: command, overrides: overrides),
            action: command.action
        )
    }

    private func liveSubtitle(for command: Command) -> String? {
        switch command.id {
        case "overlay.openEditor":
            return preferences.effective.editorCommand
        case "overlay.toggle":
            return overlays.isShowingOverlay
                ? overlays.visibleSession?.title
                : "Main CLI"
        default:
            return command.subtitle
        }
    }
}

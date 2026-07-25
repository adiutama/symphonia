import SwiftUI

@main
struct SymphoniaApp: App {
    @StateObject private var preferences: PreferencesController
    @StateObject private var workspaces: WorkspaceController
    @StateObject private var secrets: SecretStoreController
    @StateObject private var settingsNavigation: SettingsNavigation
    @StateObject private var worktrees: WorktreeController
    @StateObject private var overlays: OverlayController
    @StateObject private var commandMode: CommandModeController
    /// Command registry (ADR 0021). Drives `commandMode`'s root palette (CC.2);
    /// constructed here so it's app-wide and testable.
    @StateObject private var commandRegistry: CommandRegistry
    /// Ghostty config colors for chrome (bg/fg/scheme). Load once at launch.
    @StateObject private var ghosttyTheme: GhosttyChromeTheme

    init() {
        let preferences = PreferencesController()
        let workspaces = WorkspaceController(preferences: preferences)
        let secrets = SecretStoreController(workspaces: workspaces)
        let settingsNavigation = SettingsNavigation()
        let worktrees = WorktreeController(
            preferences: preferences,
            workspaces: workspaces,
            secrets: secrets
        )
        let overlays = OverlayController(
            preferences: preferences,
            agents: worktrees,
            secrets: secrets
        )
        let commandRegistry = CommandRegistry(providers: [
            WorkspaceCommandProvider(workspaces: workspaces, worktrees: worktrees),
            OverlayCommandProvider(),
            ChromeCommandProvider(),
        ])
        let commandMode = CommandModeController(
            preferences: preferences,
            workspaces: workspaces,
            worktrees: worktrees,
            overlays: overlays,
            settingsNavigation: settingsNavigation,
            commandRegistry: commandRegistry
        )
        _preferences = StateObject(wrappedValue: preferences)
        _workspaces = StateObject(wrappedValue: workspaces)
        _secrets = StateObject(wrappedValue: secrets)
        _settingsNavigation = StateObject(wrappedValue: settingsNavigation)
        _worktrees = StateObject(wrappedValue: worktrees)
        _overlays = StateObject(wrappedValue: overlays)
        _commandMode = StateObject(wrappedValue: commandMode)
        _commandRegistry = StateObject(wrappedValue: commandRegistry)
        _ghosttyTheme = StateObject(wrappedValue: GhosttyChromeTheme.shared)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(preferences)
                .environmentObject(workspaces)
                .environmentObject(worktrees)
                .environmentObject(secrets)
                .environmentObject(settingsNavigation)
                .environmentObject(overlays)
                .environmentObject(commandMode)
                .environmentObject(commandRegistry)
                .environmentObject(ghosttyTheme)
                .preferredColorScheme(ghosttyTheme.colorScheme)
                .ghosttyWindowChrome(ghosttyTheme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .help) {
                Button("Keymap") {
                    settingsNavigation.toggleKeymap()
                }
                .keyboardShortcut("/", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    settingsNavigation.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandMenu("Workspace") {
                Button("New Workspace") {
                    workspaces.beginCreateWorkspace()
                }
                .keyboardShortcut("n", modifiers: .command)
                Button("New Worktree") {
                    commandMode.run(.newWorktree)
                }
                .keyboardShortcut("t", modifiers: .command)
                Divider()
                Button("Next Workspace") {
                    commandMode.run(.cycleNextWorkspace)
                }
                .keyboardShortcut(.tab, modifiers: .control)
                Button("Previous Workspace") {
                    commandMode.run(.cyclePrevWorkspace)
                }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
                Button("Next Worktree") {
                    commandMode.run(.cycleNextWorktree)
                }
                .keyboardShortcut("]", modifiers: .command)
                Button("Previous Worktree") {
                    commandMode.run(.cyclePrevWorktree)
                }
                .keyboardShortcut("[", modifiers: .command)
                Button("Focus Main") {
                    commandMode.run(.focusMainRepo)
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
            CommandMenu("Overlay") {
                Button("Open Editor") {
                    commandMode.run(.openEditor)
                }
                .keyboardShortcut("e", modifiers: .command)
                Button("Overlay Terminal") {
                    commandMode.run(.createBackground)
                }
                .keyboardShortcut("j", modifiers: .command)
                Button("Overlay Switcher") {
                    commandMode.run(.showBackgroundPicker)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Toggle Overlay") {
                    commandMode.run(.toggleOverlay)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                Divider()
                Button("Reload CLI") {
                    commandMode.run(.reloadFocusedCLI)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        Window("Settings", id: SymphoniaSceneID.settings) {
            PreferencesSettingsView()
                .environmentObject(preferences)
                .environmentObject(workspaces)
                .environmentObject(secrets)
                .environmentObject(settingsNavigation)
                .environmentObject(commandRegistry)
                .environmentObject(ghosttyTheme)
                .preferredColorScheme(ghosttyTheme.colorScheme)
                .ghosttyWindowChrome(ghosttyTheme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 860, height: 560)
        .commandsRemoved()

        Window("Keymap", id: SymphoniaSceneID.keymap) {
            KeymapCheatsheetView()
                .environmentObject(preferences)
                .environmentObject(commandRegistry)
                .environmentObject(settingsNavigation)
                .environmentObject(ghosttyTheme)
                .preferredColorScheme(ghosttyTheme.colorScheme)
                .ghosttyWindowChrome(ghosttyTheme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 480, height: 640)
        .commandsRemoved()
    }
}

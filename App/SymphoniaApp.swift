import SwiftUI

@main
struct SymphoniaApp: App {
    @StateObject private var preferences: PreferencesController
    @StateObject private var workspaces: WorkspaceController
    @StateObject private var secrets: SecretStoreController
    @StateObject private var settingsNavigation: SettingsNavigation
    @StateObject private var agents: AgentController
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
        let agents = AgentController(
            preferences: preferences,
            workspaces: workspaces,
            secrets: secrets
        )
        let overlays = OverlayController(
            preferences: preferences,
            agents: agents,
            secrets: secrets
        )
        let commandRegistry = CommandRegistry(providers: [
            WorkspaceCommandProvider(workspaces: workspaces, agents: agents),
            OverlayCommandProvider(),
            ChromeCommandProvider(),
        ])
        let commandMode = CommandModeController(
            preferences: preferences,
            workspaces: workspaces,
            agents: agents,
            overlays: overlays,
            settingsNavigation: settingsNavigation,
            commandRegistry: commandRegistry
        )
        _preferences = StateObject(wrappedValue: preferences)
        _workspaces = StateObject(wrappedValue: workspaces)
        _secrets = StateObject(wrappedValue: secrets)
        _settingsNavigation = StateObject(wrappedValue: settingsNavigation)
        _agents = StateObject(wrappedValue: agents)
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
                .environmentObject(agents)
                .environmentObject(secrets)
                .environmentObject(settingsNavigation)
                .environmentObject(overlays)
                .environmentObject(commandMode)
                .environmentObject(commandRegistry)
                .environmentObject(ghosttyTheme)
                .preferredColorScheme(ghosttyTheme.colorScheme)
                .ghosttyWindowChrome(ghosttyTheme)
        }
        // Hidden titlebar + full-size content: traffic lights float over the leading
        // sidebar (Xcode / Raycast). Must be set on the Scene — applying fullSizeContentView
        // after the fact via NSViewRepresentable is unreliable.
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 720)
        .commands {
            // SwiftUI `Settings` scene forces a system titlebar — use a custom Window instead.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    settingsNavigation.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
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
    }
}

import SwiftUI

@main
struct SymphoniaApp: App {
    @StateObject private var preferences: PreferencesController
    @StateObject private var workspaces: WorkspaceController
    @StateObject private var secrets: SecretStoreController
    @StateObject private var agents: AgentController
    @StateObject private var overlays: OverlayController
    @StateObject private var commandMode: CommandModeController

    init() {
        let preferences = PreferencesController()
        let workspaces = WorkspaceController(preferences: preferences)
        let secrets = SecretStoreController(workspaces: workspaces)
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
        let commandMode = CommandModeController(
            preferences: preferences,
            workspaces: workspaces,
            agents: agents,
            overlays: overlays
        )
        _preferences = StateObject(wrappedValue: preferences)
        _workspaces = StateObject(wrappedValue: workspaces)
        _secrets = StateObject(wrappedValue: secrets)
        _agents = StateObject(wrappedValue: agents)
        _overlays = StateObject(wrappedValue: overlays)
        _commandMode = StateObject(wrappedValue: commandMode)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(preferences)
                .environmentObject(workspaces)
                .environmentObject(agents)
                .environmentObject(secrets)
                .environmentObject(overlays)
                .environmentObject(commandMode)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(after: .sidebar) {
                // Sidebar toggle is also on the status bar (⌃⌘S).
            }
        }

        Settings {
            PreferencesSettingsView()
                .environmentObject(preferences)
                .environmentObject(workspaces)
                .environmentObject(secrets)
        }
    }
}

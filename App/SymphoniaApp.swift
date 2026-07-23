import SwiftUI

@main
struct SymphoniaApp: App {
    @StateObject private var preferences: PreferencesController
    @StateObject private var workspaces: WorkspaceController
    @StateObject private var agents: AgentController

    init() {
        let preferences = PreferencesController()
        let workspaces = WorkspaceController(preferences: preferences)
        _preferences = StateObject(wrappedValue: preferences)
        _workspaces = StateObject(wrappedValue: workspaces)
        _agents = StateObject(wrappedValue: AgentController(preferences: preferences, workspaces: workspaces))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(preferences)
                .environmentObject(workspaces)
                .environmentObject(agents)
        }
        .defaultSize(width: 960, height: 720)

        Settings {
            PreferencesSettingsView()
                .environmentObject(preferences)
                .environmentObject(workspaces)
        }
    }
}

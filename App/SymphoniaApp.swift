import SwiftUI

@main
struct SymphoniaApp: App {
    @StateObject private var preferences: PreferencesController
    @StateObject private var workspaces: WorkspaceController

    init() {
        let preferences = PreferencesController()
        _preferences = StateObject(wrappedValue: preferences)
        _workspaces = StateObject(wrappedValue: WorkspaceController(preferences: preferences))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(preferences)
                .environmentObject(workspaces)
        }
        .defaultSize(width: 960, height: 640)

        Settings {
            PreferencesSettingsView()
                .environmentObject(preferences)
                .environmentObject(workspaces)
        }
    }
}

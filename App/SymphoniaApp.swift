import SwiftUI

@main
struct SymphoniaApp: App {
    @StateObject private var preferences = PreferencesController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(preferences)
        }
        .defaultSize(width: 960, height: 640)

        Settings {
            PreferencesSettingsView()
                .environmentObject(preferences)
        }
    }
}

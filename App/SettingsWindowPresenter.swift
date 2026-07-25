import SwiftUI

/// Keeps `SettingsNavigation` wired to SwiftUI `openWindow` for the custom Settings window.
/// Must live in a view hierarchy that always exists (main window), not only inside Settings.
struct SettingsWindowPresenter: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var settingsNavigation: SettingsNavigation

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                settingsNavigation.installPresenter {
                    openWindow(id: SymphoniaSceneID.settings)
                }
            }
    }
}

enum SymphoniaSceneID {
    static let settings = "settings"
}

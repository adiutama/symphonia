import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var preferences: PreferencesController
    @EnvironmentObject private var workspaces: WorkspaceController

    var body: some View {
        VStack(spacing: 12) {
            Text("Symphonia")
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text("Native host scaffold")
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Label(
                    preferences.effective.mainCLICommand.isEmpty
                        ? "bare shell"
                        : preferences.effective.mainCLICommand,
                    systemImage: "terminal"
                )
                Label(preferences.effective.editorCommand, systemImage: "pencil")
                Label(preferences.effective.leaderKey, systemImage: "keyboard")
                Label(preferences.effective.baseRef, systemImage: "arrow.triangle.branch")
                if let current = workspaces.current {
                    Label(current.slug, systemImage: "folder")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .help("Effective Setting — open Settings (⌘,) to edit Global / Workspace Setting")

            WorkspaceScaffoldView()
                .padding(.horizontal, 16)

            TerminalSurfaceView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
        }
        .frame(minWidth: 480, minHeight: 320)
    }
}

#Preview {
    let preferences = PreferencesController()
    ContentView()
        .environmentObject(preferences)
        .environmentObject(WorkspaceController(preferences: preferences))
}

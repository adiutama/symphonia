import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var preferences: PreferencesController
    @EnvironmentObject private var workspaces: WorkspaceController
    @EnvironmentObject private var agents: AgentController
    @EnvironmentObject private var secrets: SecretStoreController

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
                if let focused = agents.focused {
                    Label(focused.threeWordName, systemImage: "person")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .help("Effective Setting — open Settings (⌘,) to edit Global / Workspace Setting")

            WorkspaceScaffoldView()
                .padding(.horizontal, 16)

            AgentScaffoldView()
                .padding(.horizontal, 16)

            SecretStoreScaffoldView()
                .padding(.horizontal, 16)

            TerminalSurfaceView(
                workingDirectory: agents.focusedWorkingDirectory,
                command: agents.focusedSpawnCommand,
                spawnEnvironment: agents.focusedSpawnEnvironment
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(16)
        }
        .frame(minWidth: 480, minHeight: 320)
    }
}

#Preview {
    let preferences = PreferencesController()
    let workspaces = WorkspaceController(preferences: preferences)
    let secrets = SecretStoreController(workspaces: workspaces)
    let agents = AgentController(preferences: preferences, workspaces: workspaces, secrets: secrets)
    ContentView()
        .environmentObject(preferences)
        .environmentObject(workspaces)
        .environmentObject(agents)
        .environmentObject(secrets)
}

import SwiftUI

/// Main CLI + live Overlay PTYs. Hidden Overlays stay mounted (opacity 0) so hide ≠ quit.
struct OverlayHostView: View {
    @EnvironmentObject private var agents: AgentController
    @EnvironmentObject private var overlays: OverlayController

    var body: some View {
        ZStack {
            TerminalSurfaceView(
                workingDirectory: agents.focusedWorkingDirectory,
                command: agents.focusedSpawnCommand,
                spawnEnvironment: agents.focusedSpawnEnvironment
            )
            .zIndex(0)

            ForEach(overlays.focusedSessions) { session in
                TerminalSurfaceView(
                    workingDirectory: session.workingDirectory,
                    command: session.command,
                    spawnEnvironment: session.spawnEnvironment
                )
                .id(session.id)
                .opacity(overlays.visibleOverlayID == session.id ? 1 : 0)
                .allowsHitTesting(overlays.visibleOverlayID == session.id)
                .zIndex(overlays.visibleOverlayID == session.id ? 2 : 1)
            }
        }
    }
}

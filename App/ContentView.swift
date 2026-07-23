import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var preferences: PreferencesController
    @EnvironmentObject private var workspaces: WorkspaceController
    @EnvironmentObject private var agents: AgentController
    @EnvironmentObject private var secrets: SecretStoreController
    @EnvironmentObject private var overlays: OverlayController
    @EnvironmentObject private var commandMode: CommandModeController

    @State private var sidebarVisible = true

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                if sidebarVisible {
                    WorkspaceSidebarView()
                        .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)
                    Divider()
                }

                VStack(spacing: 0) {
                    statusBar
                    OverlayHostView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 720, minHeight: 420)

            if commandMode.isActive {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture {
                        commandMode.dismiss()
                    }

                CommandModeView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.12), value: commandMode.isActive)
        .animation(.easeInOut(duration: 0.15), value: sidebarVisible)
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Button {
                sidebarVisible.toggle()
            } label: {
                Image(systemName: sidebarVisible
                    ? "sidebar.left"
                    : "sidebar.leading")
            }
            .buttonStyle(.borderless)
            .help(sidebarVisible ? "Hide sidebar" : "Show sidebar")
            .keyboardShortcut("s", modifiers: [.command, .control])

            Text("Symphonia")
                .font(.headline)

            OverlayStatusCueView()

            Spacer(minLength: 8)

            if let session = agents.focusedSession {
                Label(session.displayTitle, systemImage: session.isMainRepo ? "shippingbox" : "person")
                    .lineLimit(1)
            } else if let current = workspaces.current {
                Label(current.slug, systemImage: "folder")
            }

            Label(
                preferences.effective.mainCLICommand.isEmpty
                    ? "bare shell"
                    : preferences.effective.mainCLICommand,
                systemImage: "terminal"
            )
            .lineLimit(1)

            if overlays.isShowingOverlay {
                Button("Hide Overlay") {
                    overlays.hide()
                }
                .help("Return to Main CLI without quitting Overlay")
            }

            if let info = commandMode.lastInfo, !commandMode.isActive {
                Text(info)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var preferences: PreferencesController
    @EnvironmentObject private var workspaces: WorkspaceController
    @EnvironmentObject private var agents: AgentController
    @EnvironmentObject private var secrets: SecretStoreController
    @EnvironmentObject private var overlays: OverlayController
    @EnvironmentObject private var commandMode: CommandModeController

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                headerBar

                if commandMode.scaffoldsExpanded {
                    WorkspaceScaffoldView()
                        .padding(.horizontal, 12)

                    AgentScaffoldView()
                        .padding(.horizontal, 12)

                    SecretStoreScaffoldView()
                        .padding(.horizontal, 12)
                }

                OverlayChromeView()
                    .padding(.horizontal, 12)

                OverlayHostView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
            .frame(minWidth: 640, minHeight: 420)

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
    }

    private var headerBar: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Symphonia")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    commandMode.scaffoldsExpanded.toggle()
                } label: {
                    Label(
                        commandMode.scaffoldsExpanded ? "Hide panels" : "Show panels",
                        systemImage: commandMode.scaffoldsExpanded
                            ? "rectangle.bottomthird.inset.filled"
                            : "rectangle.split.1x2"
                    )
                }
                .help("Collapse Workspace / Agent / Secrets scaffolds so Main CLI stays visible (⌘⇧H)")
                .keyboardShortcut("h", modifiers: [.command, .shift])

                if overlays.isShowingOverlay {
                    Button("Hide Overlay") {
                        overlays.hide()
                    }
                    .help("Return to Main CLI without quitting Overlay")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            HStack(spacing: 12) {
                Label(
                    preferences.effective.mainCLICommand.isEmpty
                        ? "bare shell"
                        : preferences.effective.mainCLICommand,
                    systemImage: "terminal"
                )
                Label(preferences.effective.editorCommand, systemImage: "pencil")
                if preferences.effective.editorPresentation == .externalApp {
                    Text("ext")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Label(preferences.effective.leaderKey, systemImage: "keyboard")
                if let current = workspaces.current {
                    Label(current.slug, systemImage: "folder")
                }
                if let focused = agents.focused {
                    Label(focused.threeWordName, systemImage: "person")
                }
                if !commandMode.scaffoldsExpanded {
                    Text("panels hidden")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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
            .help("Effective Setting — open Settings (⌘,) to edit Global / Workspace Setting")
            .padding(.horizontal, 12)
        }
    }
}

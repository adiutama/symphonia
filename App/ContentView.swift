import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var preferences: PreferencesController
    @EnvironmentObject private var workspaces: WorkspaceController
    @EnvironmentObject private var agents: AgentController
    @EnvironmentObject private var secrets: SecretStoreController
    @EnvironmentObject private var overlays: OverlayController

    /// Terminal-first default: management scaffolds collapsed so Main CLI stays usable.
    @State private var scaffoldsExpanded = false

    var body: some View {
        VStack(spacing: 8) {
            headerBar

            if scaffoldsExpanded {
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
    }

    private var headerBar: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Symphonia")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    scaffoldsExpanded.toggle()
                } label: {
                    Label(
                        scaffoldsExpanded ? "Hide panels" : "Show panels",
                        systemImage: scaffoldsExpanded ? "rectangle.bottomthird.inset.filled" : "rectangle.split.1x2"
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
                if !scaffoldsExpanded {
                    Text("panels hidden")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .help("Effective Setting — open Settings (⌘,) to edit Global / Workspace Setting")
            .padding(.horizontal, 12)
        }
    }
}

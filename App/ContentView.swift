import AppKit
import SwiftUI

/// Sidebar display mode: fully expanded, or a narrow rail that keeps focus/switch affordances.
enum SidebarMode: String {
    case expanded
    case rail
}

struct ContentView: View {
    @EnvironmentObject private var preferences: PreferencesController
    @EnvironmentObject private var workspaces: WorkspaceController
    @EnvironmentObject private var agents: AgentController
    @EnvironmentObject private var secrets: SecretStoreController
    @EnvironmentObject private var overlays: OverlayController
    @EnvironmentObject private var commandMode: CommandModeController

    @AppStorage("sidebarMode") private var sidebarModeRaw: String = SidebarMode.expanded.rawValue
    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 240
    @State private var dragStartWidth: Double?

    private let sidebarMinWidth: Double = 180
    private let sidebarMaxWidth: Double = 400
    private let sidebarRailWidth: CGFloat = 52

    private var sidebarMode: SidebarMode {
        SidebarMode(rawValue: sidebarModeRaw) ?? .expanded
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                if sidebarMode == .expanded {
                    WorkspaceSidebarView()
                        .frame(width: sidebarWidth)
                    resizeDivider
                } else {
                    sidebarRail
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
        .animation(.easeInOut(duration: 0.15), value: sidebarModeRaw)
    }

    /// Draggable divider between the expanded sidebar and the workspace content; persists width.
    private var resizeDivider: some View {
        Divider()
            .contentShape(Rectangle().inset(by: -4))
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let base = dragStartWidth ?? sidebarWidth
                        if dragStartWidth == nil {
                            dragStartWidth = base
                        }
                        let proposed = base + value.translation.width
                        sidebarWidth = min(max(proposed, sidebarMinWidth), sidebarMaxWidth)
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                    }
            )
    }

    /// Narrow rail shown when the sidebar is collapsed: keeps expand control + current
    /// Workspace’s Main/Worktree affordances so Operator can still see focus / switch sessions.
    private var sidebarRail: some View {
        VStack(spacing: 6) {
            Button {
                sidebarModeRaw = SidebarMode.expanded.rawValue
            } label: {
                Image(systemName: "sidebar.leading")
            }
            .buttonStyle(.borderless)
            .help("Expand sidebar")
            .padding(.top, 10)

            Divider()
                .padding(.horizontal, 10)

            if let current = workspaces.current {
                ScrollView {
                    VStack(spacing: 6) {
                        railMark(
                            systemImage: "shippingbox",
                            isFocused: isMainFocused(current),
                            help: "Main · \(current.slug)"
                        ) {
                            workspaces.select(current)
                            agents.focusMain(for: current)
                        }

                        ForEach(agents.agents(in: current)) { agent in
                            railMark(
                                systemImage: "arrow.triangle.branch",
                                isFocused: agents.focusedSession?.agent?.id == agent.id,
                                help: agent.primaryLabel
                            ) {
                                workspaces.select(current)
                                agents.focus(agent)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(width: sidebarRailWidth)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func railMark(
        systemImage: String,
        isFocused: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(isFocused ? Color.accentColor : .secondary)
                .frame(width: 32, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isFocused ? Color.accentColor.opacity(0.18) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func isMainFocused(_ workspace: WorkspaceSummary) -> Bool {
        guard workspaces.current?.id == workspace.id,
              let session = agents.focusedSession,
              case .mainRepo = session
        else { return false }
        return true
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Button {
                sidebarModeRaw = (sidebarMode == .expanded ? SidebarMode.rail : SidebarMode.expanded).rawValue
            } label: {
                Image(systemName: sidebarMode == .expanded
                    ? "sidebar.left"
                    : "sidebar.leading")
            }
            .buttonStyle(.borderless)
            .help(sidebarMode == .expanded ? "Collapse sidebar" : "Expand sidebar")
            .keyboardShortcut("s", modifiers: [.command, .control])

            Text("Symphonia")
                .font(.headline)

            OverlayStatusCueView()

            Spacer(minLength: 8)

            if let session = agents.focusedSession {
                Label(session.displayTitle, systemImage: session.isMainRepo ? "shippingbox" : "arrow.triangle.branch")
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

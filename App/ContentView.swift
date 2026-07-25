import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var workspaces: WorkspaceController
    @EnvironmentObject private var worktrees: WorktreeController
    @EnvironmentObject private var secrets: SecretStoreController
    @EnvironmentObject private var commandMode: CommandModeController
    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme

    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 240
    @State private var dragStartWidth: Double?

    private let sidebarMinWidth: Double = 180
    private let sidebarMaxWidth: Double = 400

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                WorkspaceSidebarView()
                    .frame(width: sidebarWidth)
                resizeDivider

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
        .background(ghosttyTheme.background.ignoresSafeArea())
        // Extend under the hidden titlebar so the sidebar owns the traffic-light column.
        .ignoresSafeArea(.container, edges: .top)
        .symphoniaTitlebarChrome()
        .animation(.easeOut(duration: 0.12), value: commandMode.isActive)
        .background(SettingsWindowPresenter())
    }

    /// Draggable divider between the sidebar and the workspace content; persists width.
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

    private var statusBar: some View {
        HStack(spacing: 10) {
            OverlayStatusCueView()

            Spacer(minLength: 8)
                .windowDragRegion()
                .help("Drag to move window")

            if let session = worktrees.focusedSession,
               let slug = statusBarWorkspaceSlug(for: session) {
                Label(session.statusBarContext(workspaceSlug: slug), systemImage: session.statusBarIcon)
                    .lineLimit(1)
            } else if let current = workspaces.current {
                Text(displayLowercased(current.slug))
                    .lineLimit(1)
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
        // Main column sits right of sidebar — light top pad under transparent titlebar.
        .padding(.top, 2)
        .background(ghosttyTheme.bar)
    }

    private func statusBarWorkspaceSlug(for session: FocusedSession) -> String? {
        if case .mainRepo(_, _, let slug) = session {
            return slug
        }
        return workspaces.current?.slug
    }
}

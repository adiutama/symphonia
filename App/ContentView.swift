import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var commandCenter: CommandCenterController
    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme
    @EnvironmentObject private var preferences: PreferencesController
    @EnvironmentObject private var workspaces: WorkspaceController
    @EnvironmentObject private var worktrees: WorktreeController
    @EnvironmentObject private var overlays: OverlayController

    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 240
    @State private var dragStartWidth: Double?
    @State private var showGlance = false

    private let sidebarMinWidth: Double = 180
    private let sidebarMaxWidth: Double = 400
    /// Matches `WorkspaceSidebarView` titlebar band so meta vertically aligns with chrome.
    private let titlebarBandHeight: CGFloat = 52
    private let titlebarEdgeInset: CGFloat = 14

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                WorkspaceSidebarView()
                    .frame(width: sidebarWidth)
                    .overlay(alignment: .trailing) {
                        SoftPaneHairline()
                    }
                    .overlay(alignment: .trailing) {
                        resizeHandle
                    }

                OverlayHostView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ghosttyTheme.background.ignoresSafeArea(.container, edges: .top))
                    .overlay(alignment: .topLeading) {
                        projectMetaLayer
                            // Sit in the transparent titlebar band (level with traffic lights),
                            // not the content safe area on top of the terminal.
                            .ignoresSafeArea(.container, edges: .top)
                    }
                    .overlay(alignment: .topTrailing) {
                        glanceLayer
                    }
            }
            .frame(minWidth: 720, minHeight: 420)

            if commandCenter.isActive {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture {
                        commandCenter.dismiss()
                    }

                CommandCenterView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        // When glass is on, keep the window clear under the sidebar so Liquid Glass /
        // vibrancy can sample the desktop. The terminal host paints its own solid fill.
        .background {
            if preferences.preferences.chromeGlass {
                Color.clear
            } else {
                ghosttyTheme.background
            }
        }
        .toolbar {
            // Expand Glance — trailing edge (not clustered with traffic lights).
            ToolbarSpacer(.flexible)
            ToolbarItem {
                Button {
                    showGlance.toggle()
                } label: {
                    GlanceToggleIcon(isExpanded: showGlance)
                        .foregroundStyle(ghosttyTheme.foreground)
                        .frame(width: 18, height: 14)
                }
                .help(showGlance ? "Collapse Glance" : "Expand Glance (Activity Manager)")
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .symphoniaTitlebarChrome()
        .animation(.easeOut(duration: 0.12), value: commandCenter.isActive)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: showGlance)
        .background(SettingsWindowPresenter())
        .sheet(isPresented: Binding(
            get: { !preferences.preferences.onboardingCompleted },
            set: { presented in
                if !presented {
                    preferences.preferences.onboardingCompleted = true
                    preferences.save()
                }
            }
        )) {
            OnboardingView()
        }
        .alert(
            "Cannot Create Worktree",
            isPresented: Binding(
                get: { worktrees.alertMessage != nil },
                set: { presented in
                    if !presented, worktrees.alertMessage != nil {
                        worktrees.dismissAlert()
                    }
                }
            )
        ) {
            Button("Okay", role: .cancel) {
                worktrees.dismissAlert()
            }
        } message: {
            Text(worktrees.alertMessage ?? "")
        }
    }

    /// Project slug + path — content titlebar leading edge, no toolbar pill wrapper.
    @ViewBuilder
    private var projectMetaLayer: some View {
        if !workspaces.isCreateFlowActive, let workspace = workspaces.current {
            VStack(alignment: .leading, spacing: 1) {
                Text(displayLowercased(workspace.slug))
                    .font(.headline)
                    .foregroundStyle(ghosttyTheme.foreground)
                    .lineLimit(1)
                Text(pathCaption(for: workspace))
                    .font(.caption)
                    .foregroundStyle(ghosttyTheme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: 280, alignment: .leading)
            .padding(.leading, titlebarEdgeInset)
            .frame(height: titlebarBandHeight, alignment: .center)
            .windowDragRegion()
        } else if let bootstrap = workspaces.createBootstrap {
            VStack(alignment: .leading, spacing: 1) {
                Text(displayLowercased(bootstrap.summary.slug))
                    .font(.headline)
                    .foregroundStyle(ghosttyTheme.foreground)
                    .lineLimit(1)
                Text(bootstrap.failed ? "Setup failed" : bootstrap.title)
                    .font(.caption)
                    .foregroundStyle(ghosttyTheme.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: 280, alignment: .leading)
            .padding(.leading, titlebarEdgeInset)
            .frame(height: titlebarBandHeight, alignment: .center)
            .windowDragRegion()
        }
    }

    /// Expanded Glance under the titlebar toggle — grows from trailing edge; no outside dismiss.
    @ViewBuilder
    private var glanceLayer: some View {
        if showGlance {
            GlanceHUD()
                .padding(.top, 6)
                .padding(.trailing, 14)
                .transition(
                    .asymmetric(
                        insertion: .opacity
                            .combined(with: .scale(scale: 0.92, anchor: .topTrailing))
                            .combined(with: .move(edge: .trailing)),
                        removal: .opacity
                            .combined(with: .scale(scale: 0.96, anchor: .topTrailing))
                    )
                )
        }
    }

    private func pathCaption(for workspace: WorkspaceSummary) -> String {
        if let focused = worktrees.focusedSession {
            return abbreviatedPath(focused.workingDirectory)
        }
        return abbreviatedPath(workspace.dataDirURL.path)
    }

    private func abbreviatedPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    /// Invisible resize hit-target on the sidebar’s trailing edge (no gap / seam in the HStack).
    private var resizeHandle: some View {
        Color.clear
            .frame(width: 8)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
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
}

/// Glance toggle — list glyph (Activity Manager expand/collapse).
private struct GlanceToggleIcon: View {
    var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3.5) {
            row
            row
        }
        .opacity(isExpanded ? 1 : 0.92)
        .accessibilityHidden(true)
    }

    private var row: some View {
        HStack(spacing: 3.5) {
            Circle()
                .fill(.primary)
                .frame(width: 3.5, height: 3.5)
            Capsule()
                .fill(.primary)
                .frame(width: 11, height: 2)
        }
    }
}

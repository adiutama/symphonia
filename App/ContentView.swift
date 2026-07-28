import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var commandMode: CommandModeController
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
                    .overlay(alignment: .topTrailing) {
                        glanceLayer
                    }
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
            ToolbarItem(placement: .principal) {
                projectMeta
            }

            // Glance HUD toggle — trailing edge (not clustered with traffic lights).
            ToolbarSpacer(.flexible)
            ToolbarItem {
                Button {
                    showGlance.toggle()
                } label: {
                    Image(systemName: "viewfinder")
                        .foregroundStyle(ghosttyTheme.foreground)
                }
                .help("Glance")
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .symphoniaTitlebarChrome()
        .animation(.easeOut(duration: 0.12), value: commandMode.isActive)
        .animation(.easeOut(duration: 0.14), value: showGlance)
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
    }

    /// Floating Glance chip under the titlebar toggle (option B). Toggle only — no outside dismiss.
    @ViewBuilder
    private var glanceLayer: some View {
        if showGlance {
            GlanceHUD()
                .padding(.top, 6)
                .padding(.trailing, 14)
                .transition(
                    .opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing))
                )
        }
    }

    @ViewBuilder
    private var projectMeta: some View {
        if let workspace = workspaces.current {
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

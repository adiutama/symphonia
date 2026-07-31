import SwiftUI

/// Main CLI surfaces (one live PTY per opened session) + Overlay peeks.
///
/// Pane chrome (Peek requirements): kind + title + Back. No tabs; kill only via CC nest.
struct OverlayHostView: View {
    @EnvironmentObject private var workspaces: WorkspaceController
    @EnvironmentObject private var worktrees: WorktreeController
    @EnvironmentObject private var overlays: OverlayController
    @EnvironmentObject private var preferences: PreferencesController
    @EnvironmentObject private var settingsNavigation: SettingsNavigation
    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme

    var body: some View {
        ZStack {
            // Terminal host stays solid — glass is for the sidebar only.
            ghosttyTheme.background

            ForEach(worktrees.openedMainCLISessions) { slot in
                let isFocused = worktrees.focusedSession?.id == slot.id
                let isVisible = isFocused && !overlays.isShowingOverlay && !workspaces.isCreateFlowActive
                ZStack {
                    TerminalSurfaceView(
                        workingDirectory: slot.workingDirectory,
                        command: slot.command,
                        spawnEnvironment: slot.spawnEnvironment,
                        isActive: isVisible && !slot.processExited,
                        onProcessExit: {
                            worktrees.handleMainCLIProcessExit(sessionId: slot.id)
                        }
                    )
                    .id(slot.viewIdentity)

                    if slot.processExited {
                        mainCLIExitedState(sessionId: slot.id)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(isFocused && !workspaces.isCreateFlowActive ? 1 : 0)
                .allowsHitTesting(isVisible)
                .zIndex(isFocused ? 0 : -1)
            }

            if let bootstrap = workspaces.createBootstrap {
                CreateProjectBootstrapPane(session: bootstrap)
                    .zIndex(0)
            } else if workspaces.pendingCreateWorkspace {
                CreateProjectCanvas()
                    .zIndex(0)
            } else if worktrees.openedMainCLISessions.isEmpty {
                // Above the solid background fill; overlays use zIndex ≥ 1.
                mainEmptyState
                    .zIndex(0)
            }

            if overlays.isShowingOverlay {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .onTapGesture { overlays.hide() }
                    .zIndex(1)
            }

            // Keep every Overlay surface mounted (like Main CLI slots). Opacity-hide when
            // not peeked or when its Worktree is not focused — never unmount until Close.
            ForEach(overlays.sessions) { session in
                let belongsToFocus = worktrees.focusedSession?.id == session.sessionId
                let isVisible = belongsToFocus && overlays.visibleOverlayID == session.id
                GeometryReader { proxy in
                    overlayPane(session: session, isVisible: isVisible)
                        .padding(24)
                        .frame(width: proxy.size.width * 0.92, height: proxy.size.height * 0.88)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .opacity(isVisible ? 1 : 0)
                .allowsHitTesting(isVisible)
                .zIndex(isVisible ? 2 : -1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if let error = overlays.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(ghosttyTheme.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(ghosttyTheme.panel.opacity(0.92))
            }
        }
        .animation(.easeOut(duration: 0.15), value: overlays.visibleOverlayID)
        .animation(.easeOut(duration: 0.12), value: worktrees.focusedSession?.id)
        .animation(.easeOut(duration: 0.12), value: overlays.lastError)
    }

    private var mainEmptyState: some View {
        let hasWorkspaces = !workspaces.workspaces.isEmpty
        return VStack(spacing: 16) {
            Image(systemName: hasWorkspaces ? "sidebar.left" : "square.stack.3d.up")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(ghosttyTheme.accent)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(hasWorkspaces ? "Select a Project" : "No Project yet")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ghosttyTheme.foreground)
                Text(
                    hasWorkspaces
                        ? "Pick a Project in the sidebar to open its Main CLI."
                        : "Create a Project to open its Main CLI — your agent’s home stage."
                )
                .font(.subheadline)
                .foregroundStyle(ghosttyTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Button("New Project") {
                    workspaces.beginCreateWorkspace()
                }
                .buttonStyle(.borderedProminent)
                .tint(ghosttyTheme.accent)
                .keyboardShortcut("n", modifiers: [.command, .shift])

                if !hasWorkspaces {
                    Button("Open Settings") {
                        settingsNavigation.openSettings()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .accessibilityElement(children: .combine)
    }

    private func overlayPane(session: OverlaySession, isVisible: Bool) -> some View {
        VStack(spacing: 0) {
            sheetHeader(session)
            SoftHairline(horizontalPadding: 10)
            TerminalSurfaceView(
                workingDirectory: session.workingDirectory,
                command: session.command,
                spawnEnvironment: session.spawnEnvironment,
                isActive: isVisible,
                onProcessExit: {
                    overlays.handleProcessExit(session.id)
                }
            )
            .id(session.id)
        }
        .chromeFloatingSurface(
            glass: preferences.preferences.chromeGlass,
            solid: ghosttyTheme.panel,
            cornerRadius: 12
        )
        .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
    }

    private func mainCLIExitedState(sessionId: String) -> some View {
        VStack(spacing: 14) {
            Text("Main CLI exited")
                .font(.title3.weight(.semibold))
                .foregroundStyle(ghosttyTheme.foreground)
            Text("The process quit repeatedly. Reload to start again.")
                .font(.subheadline)
                .foregroundStyle(ghosttyTheme.secondaryText)
                .multilineTextAlignment(.center)
            Button("Reload CLI") {
                worktrees.reloadOpenedMainCLI(sessionId: sessionId)
            }
            .buttonStyle(.borderedProminent)
            .tint(ghosttyTheme.accent)
            .keyboardShortcut("r", modifiers: .command)
            .padding(.top, 4)
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(ghosttyTheme.background.opacity(0.92))
    }

    private func sheetHeader(_ session: OverlaySession) -> some View {
        HStack(spacing: 8) {
            Text(session.kind == .editor ? "Editor" : "Shell")
                .font(.caption2.weight(.semibold).monospaced())
                .foregroundStyle(ghosttyTheme.secondaryText)
                .tracking(0.4)

            Text(session.title)
                .font(.subheadline)
                .foregroundStyle(ghosttyTheme.foreground.opacity(0.85))
                .lineLimit(1)

            Spacer(minLength: 8)

            Button("Back") {
                overlays.hide()
            }
            .font(.caption.weight(.medium))
            .buttonStyle(.plain)
            .foregroundStyle(ghosttyTheme.secondaryText)
            .help("Hide Overlay (keeps running); End via Overlay Switcher")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

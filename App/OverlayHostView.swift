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
                let isVisible = worktrees.focusedSession?.id == slot.id && !overlays.isShowingOverlay
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
                .opacity(worktrees.focusedSession?.id == slot.id ? 1 : 0)
                .allowsHitTesting(isVisible)
                .zIndex(worktrees.focusedSession?.id == slot.id ? 0 : -1)
            }

            if worktrees.openedMainCLISessions.isEmpty {
                mainEmptyState
                    .zIndex(-1)
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
        VStack(spacing: 14) {
            if workspaces.workspaces.isEmpty {
                Text("No Workspace yet")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ghosttyTheme.foreground)
                Text("Create a Workspace to open its Main CLI.")
                    .font(.subheadline)
                    .foregroundStyle(ghosttyTheme.secondaryText)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button("Create Workspace") {
                        workspaces.beginCreateWorkspace()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ghosttyTheme.accent)

                    Button("Open Settings") {
                        settingsNavigation.openSettings()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            } else {
                Text("Select a Workspace")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ghosttyTheme.foreground)
                Text("Pick a Workspace in the sidebar, then open Main or a Worktree.")
                    .font(.subheadline)
                    .foregroundStyle(ghosttyTheme.secondaryText)
                    .multilineTextAlignment(.center)

                Button("Create Workspace") {
                    workspaces.beginCreateWorkspace()
                }
                .buttonStyle(.borderedProminent)
                .tint(ghosttyTheme.accent)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
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
            Text(session.kind == .editor ? "EDITOR" : "BG")
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
            .help("Toggle Overlay (process stays alive); kill via Overlay Switcher")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

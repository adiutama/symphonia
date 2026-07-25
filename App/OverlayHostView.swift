import SwiftUI

/// Main CLI surfaces (one live PTY per opened session) + Overlay peeks.
///
/// Pane chrome (Peek requirements): kind + title + Back. No tabs; kill only via CC nest.
struct OverlayHostView: View {
    @EnvironmentObject private var worktrees: WorktreeController
    @EnvironmentObject private var overlays: OverlayController
    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme

    var body: some View {
        ZStack {
            ghosttyTheme.background

            ForEach(worktrees.openedMainCLISessions) { slot in
                let isVisible = worktrees.focusedSession?.id == slot.id && !overlays.isShowingOverlay
                TerminalSurfaceView(
                    workingDirectory: slot.workingDirectory,
                    command: slot.command,
                    spawnEnvironment: slot.spawnEnvironment,
                    isActive: isVisible
                )
                .id(slot.viewIdentity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(worktrees.focusedSession?.id == slot.id ? 1 : 0)
                .allowsHitTesting(isVisible)
                .zIndex(worktrees.focusedSession?.id == slot.id ? 0 : -1)
            }

            if worktrees.openedMainCLISessions.isEmpty {
                Text("Select Main Repo or a Worktree")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(-1)
            }

            if overlays.isShowingOverlay {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .onTapGesture { overlays.hide() }
                    .zIndex(1)
            }

            ForEach(overlays.focusedSessions) { session in
                let isVisible = overlays.visibleOverlayID == session.id
                GeometryReader { proxy in
                    overlayPane(session: session, isVisible: isVisible)
                        .padding(24)
                        .frame(width: proxy.size.width * 0.92, height: proxy.size.height * 0.88)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .opacity(isVisible ? 1 : 0)
                .allowsHitTesting(isVisible)
                .zIndex(isVisible ? 2 : 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.15), value: overlays.visibleOverlayID)
        .animation(.easeOut(duration: 0.12), value: worktrees.focusedSession?.id)
    }

    private func overlayPane(session: OverlaySession, isVisible: Bool) -> some View {
        VStack(spacing: 0) {
            sheetHeader(session)
            Divider().opacity(0.25)
            TerminalSurfaceView(
                workingDirectory: session.workingDirectory,
                command: session.command,
                spawnEnvironment: session.spawnEnvironment,
                isActive: isVisible
            )
            .id(session.id)
        }
        .background(ghosttyTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
    }

    private func sheetHeader(_ session: OverlaySession) -> some View {
        HStack(spacing: 8) {
            Text(session.kind == .editor ? "EDITOR" : "BG")
                .font(.caption2.weight(.semibold).monospaced())
                .foregroundStyle(.secondary)
                .tracking(0.4)

            Text(session.title)
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(1)

            Spacer(minLength: 8)

            Button("Back") {
                overlays.hide()
            }
            .font(.caption.weight(.medium))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Hide Overlay (process stays alive); kill via Overlay Switcher")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

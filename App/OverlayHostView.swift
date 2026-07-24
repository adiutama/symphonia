import SwiftUI

/// Main CLI surfaces (one live PTY per opened session) + Overlay peeks.
///
/// Switching Main/Agent **hides** other Main CLI PTYs (opacity 0) instead of destroying them.
/// Tear-down happens when the session is removed or the Workspace changes (`AgentController`).
struct OverlayHostView: View {
    @EnvironmentObject private var agents: AgentController
    @EnvironmentObject private var overlays: OverlayController

    var body: some View {
        ZStack {
            ForEach(agents.openedMainCLISessions) { slot in
                let isVisible = agents.focusedSession?.id == slot.id && !overlays.isShowingOverlay
                TerminalSurfaceView(
                    workingDirectory: slot.workingDirectory,
                    command: slot.command,
                    spawnEnvironment: slot.spawnEnvironment,
                    isActive: isVisible
                )
                .id(slot.viewIdentity)
                .opacity(agents.focusedSession?.id == slot.id ? 1 : 0)
                .allowsHitTesting(isVisible)
                .zIndex(agents.focusedSession?.id == slot.id ? 0 : -1)
            }

            if agents.openedMainCLISessions.isEmpty {
                Color.black
                    .overlay {
                        Text("Select Main Repo or an Agent")
                            .foregroundStyle(.secondary)
                    }
                    .zIndex(-2)
            }

            if overlays.isShowingOverlay {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .onTapGesture { overlays.hide() }
                    .zIndex(1)
            }

            ForEach(overlays.focusedSessions) { session in
                let isVisible = overlays.visibleOverlayID == session.id
                // Tracks the parent window: sized as a fraction of the host, not fixed
                // points, so the peek stays roomy on large windows and shrinks with them.
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
        .animation(.easeOut(duration: 0.15), value: overlays.visibleOverlayID)
        .animation(.easeOut(duration: 0.12), value: agents.focusedSession?.id)
    }

    private func overlayPane(session: OverlaySession, isVisible: Bool) -> some View {
        VStack(spacing: 0) {
            sheetHeader(session)
            Divider()
            TerminalSurfaceView(
                workingDirectory: session.workingDirectory,
                command: session.command,
                spawnEnvironment: session.spawnEnvironment,
                isActive: isVisible
            )
            .id(session.id)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
    }

    private func sheetHeader(_ session: OverlaySession) -> some View {
        HStack(spacing: 8) {
            Text(session.kind == .editor ? "Editor" : "Background")
                .font(.headline)
            Text(session.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if session.kind == .background {
                Button("Close", role: .destructive) {
                    overlays.close(session.id)
                }
                .help("Quit this Overlay PTY (unlike Hide)")
            }
            // Demoted: primary hide path is Command Center `/hide` `/x` (or backdrop tap).
            Button {
                overlays.hide()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Hide Overlay (also: /hide in Command Center); process stays alive")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

import SwiftUI

/// Main CLI surfaces (one live PTY per opened session) + Overlay peeks.
///
/// Switching Main/Worktree **hides** other Main CLI PTYs (opacity 0) instead of destroying them.
/// Tear-down happens when the session is removed or the Workspace changes (`WorktreeController`).
struct OverlayHostView: View {
    @EnvironmentObject private var worktrees: WorktreeController
    @EnvironmentObject private var overlays: OverlayController
    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme

    var body: some View {
        ZStack {
            // Expand the ZStack to the proposed host size so Main CLI surfaces fill it.
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
        HStack(spacing: 6) {
            // Sibling switcher inside the Overlay (C.7) — not a third column.
            if overlays.focusedSessions.count > 1 {
                overlayTabs(active: session)
            } else {
                Image(systemName: session.kind == .editor ? "pencil" : "arrow.triangle.2.circlepath")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel(session.kind == .editor ? "Editor" : "Background")

                Text(session.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if session.kind == .background {
                Button("close") {
                    overlays.close(session.id)
                }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("Quit this Overlay PTY (unlike Hide)")
            }

            // Demoted: primary hide path is Command Center `/hide` `/x` (or backdrop tap).
            Button {
                overlays.hide()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.tertiary)
            .help("Hide Overlay (also: /hide in Command Center); process stays alive")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func overlayTabs(active: OverlaySession) -> some View {
        HStack(spacing: 2) {
            ForEach(overlays.focusedSessions) { peer in
                let isSelected = peer.id == active.id
                Button {
                    overlays.peek(peer.id)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: peer.kind == .editor ? "pencil" : "arrow.triangle.2.circlepath")
                            .font(.caption2)
                        Text(tabLabel(peer))
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .foregroundStyle(isSelected ? Color.primary.opacity(0.85) : Color.secondary.opacity(0.55))
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(isSelected ? Color.primary.opacity(0.08) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .help(peer.title)
            }
        }
    }

    private func tabLabel(_ session: OverlaySession) -> String {
        switch session.kind {
        case .editor:
            return "editor"
        case .background:
            // Keep short — full title in help.
            let raw = session.title.replacingOccurrences(of: "BG: ", with: "")
            return raw.count > 14 ? String(raw.prefix(12)) + "…" : raw.lowercased()
        }
    }
}

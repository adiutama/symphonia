import SwiftUI

/// Overlay switcher, Editor/Background actions, and Status Cue chrome (P6 scaffold).
struct OverlayChromeView: View {
    @EnvironmentObject private var agents: AgentController
    @EnvironmentObject private var overlays: OverlayController
    @EnvironmentObject private var preferences: PreferencesController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Overlays")
                    .font(.headline)

                statusCue

                Spacer(minLength: 8)

                if overlays.isShowingOverlay {
                    if let visible = overlays.visibleSession {
                        Text(visible.kind == .editor ? "EDITOR" : "BG")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(visible.kind == .editor ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        Text(visible.title)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    Button("Hide → Main CLI") {
                        overlays.hide()
                    }
                    .help("Hide Overlay; process stays alive (ADR 0006/0007)")
                } else {
                    Text("Main CLI")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Button("Open Editor") {
                    overlays.openEditor()
                }
                .disabled(agents.focused == nil)
                .help(
                    preferences.effective.editorPresentation == .externalApp
                        ? "Launch external editor (\(preferences.effective.editorCommand))"
                        : "Peek Editor Overlay (\(preferences.effective.editorCommand))"
                )

                TextField("bg command (empty = shell)", text: $overlays.draftBackgroundCommand)
                    .textFieldStyle(.roundedBorder)
                    .disabled(agents.focused == nil)

                Button("Create Background") {
                    overlays.createBackgroundCLI()
                }
                .disabled(agents.focused == nil)

                if let visibleID = overlays.visibleOverlayID {
                    Button("Close Overlay", role: .destructive) {
                        overlays.close(visibleID)
                    }
                    .help("Quit this Overlay PTY (unlike Hide)")
                }
            }

            if !overlays.focusedSessions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(overlays.focusedSessions) { session in
                            Button {
                                if overlays.visibleOverlayID == session.id {
                                    overlays.hide()
                                } else {
                                    overlays.peek(session.id)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: session.kind == .editor ? "pencil" : "terminal")
                                    Text(session.title)
                                        .font(session.kind == .editor ? .caption.weight(.semibold) : .caption)
                                    if overlays.visibleOverlayID == session.id {
                                        Text("●")
                                            .font(.caption2)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    session.kind == .editor
                                        ? Color.accentColor.opacity(overlays.visibleOverlayID == session.id ? 0.45 : 0.22)
                                        : Color.secondary.opacity(overlays.visibleOverlayID == session.id ? 0.35 : 0.12)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                            .help(session.kind == .editor ? "Editor Overlay (higher weight)" : "Background CLI Overlay")
                        }
                    }
                }
            }

            if let info = overlays.lastInfo {
                Text(info)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let error = overlays.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// Calm cue for running Background CLIs while on Main CLI (ADR 0008 / P6.7).
    @ViewBuilder
    private var statusCue: some View {
        let count = overlays.focusedBackgroundCount
        if count > 0 {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.orange.opacity(0.9))
                    .frame(width: 7, height: 7)
                Text("\(count) BG")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .help("\(count) Background CLI(s) running — peek via switcher")
            .accessibilityLabel("\(count) background CLIs running")
        }
    }
}

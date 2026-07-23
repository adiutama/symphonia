import SwiftUI

/// Compact Status Cue for running Background CLIs (permanent Overlay toolbar demoted).
struct OverlayStatusCueView: View {
    @EnvironmentObject private var overlays: OverlayController
    @EnvironmentObject private var commandMode: CommandModeController

    var body: some View {
        HStack(spacing: 8) {
            statusCue

            if overlays.isShowingOverlay, let visible = overlays.visibleSession {
                Text(visible.kind == .editor ? "EDITOR" : "BG")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        visible.kind == .editor
                            ? Color.accentColor.opacity(0.35)
                            : Color.secondary.opacity(0.2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            Menu {
                Button("Open Editor") {
                    overlays.openEditor()
                }
                Button("Create Background CLI") {
                    overlays.createBackgroundCLI()
                }
                if !overlays.focusedSessions.isEmpty {
                    Divider()
                    ForEach(overlays.focusedSessions) { session in
                        Button {
                            if overlays.visibleOverlayID == session.id {
                                overlays.hide()
                            } else {
                                overlays.peek(session.id)
                            }
                        } label: {
                            Text(session.title)
                        }
                    }
                }
                Divider()
                Button("Command Mode…") {
                    commandMode.enter()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .help("Overlay actions (prefer Command Mode)")
        }
    }

    @ViewBuilder
    private var statusCue: some View {
        let count = overlays.focusedBackgroundCount
        if count > 0 {
            Button {
                if !commandMode.isActive {
                    commandMode.enter()
                }
                commandMode.run(.showBackgroundPicker)
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.orange.opacity(0.9))
                        .frame(width: 7, height: 7)
                    Text("\(count) BG")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help("\(count) Background CLI(s) running — peek via Command Mode")
            .accessibilityLabel("\(count) background CLIs running")
        }
    }
}

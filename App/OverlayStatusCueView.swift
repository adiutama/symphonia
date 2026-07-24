import SwiftUI

/// Calm Status Cue for running Background CLIs — dot (and quiet count when >1).
struct OverlayStatusCueView: View {
    @EnvironmentObject private var overlays: OverlayController
    @EnvironmentObject private var commandMode: CommandModeController

    var body: some View {
        statusCue
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
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color.secondary.opacity(0.55))
                        .frame(width: 6, height: 6)
                    if count > 1 {
                        Text("\(count)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("\(count) background CLI\(count == 1 ? "" : "s") running — Command Center to peek")
            .accessibilityLabel("\(count) background CLIs running")
        }
    }
}

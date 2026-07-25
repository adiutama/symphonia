import AppKit
import SwiftUI

/// Record a Leader-style key combination into a binding string (`ctrl+p`).
struct KeyChordField: View {
    @Binding var chord: String
    /// When true, recorded chords must include ctrl, opt, or cmd (Command Center shortcuts).
    var requireModifier: Bool = false

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Text(displayLabel)
                .font(.body.monospaced())
                .foregroundStyle(chord.isEmpty ? .secondary : .primary)
                .frame(minWidth: 72, alignment: .trailing)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Button(isRecording ? "Listening…" : "Record") {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }
            .buttonStyle(.bordered)

            if !chord.isEmpty {
                Button("Clear") {
                    chord = ""
                    stopRecording()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .onDisappear { stopRecording() }
    }

    private var displayLabel: String {
        if isRecording { return "…" }
        if chord.isEmpty { return "None" }
        return LeaderKeyBinding.parse(chord)?.displaySymbolString ?? chord
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape — cancel
                Task { @MainActor in
                    stopRecording()
                }
                return nil
            }
            if let binding = LeaderKeyBinding.from(event: event) {
                if requireModifier {
                    let mods = binding.modifiers.intersection([.control, .option, .command])
                    guard !mods.isEmpty else { return nil }
                }
                let stored = binding.storageString
                Task { @MainActor in
                    chord = stored
                    stopRecording()
                }
                return nil
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
    }
}

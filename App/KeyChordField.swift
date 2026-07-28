import AppKit
import SwiftUI

/// Click-to-record key chord (`cmd+shift+p`). Esc cancels; Delete clears while listening.
struct KeyChordField: View {
    @Binding var chord: String
    /// When true, recorded chords must include ctrl, opt, or cmd.
    var requireModifier: Bool = false
    /// Placeholder when empty (e.g. "Record Hotkey").
    var emptyLabel: String = "Record Hotkey"
    /// Stretch to fill a table cell.
    var fillsWidth: Bool = false

    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        } label: {
            Text(displayLabel)
                .font(.body.monospaced())
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, fillsWidth ? 0 : 10)
                .padding(.vertical, fillsWidth ? 2 : 5)
                .background(fillsWidth ? Color.clear : ghosttyTheme.control)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            isRecording ? ghosttyTheme.accent : Color.clear,
                            lineWidth: 1.5
                        )
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        .help(isRecording ? "Press a key combination… (Esc to cancel)" : "Click to record")
        .onDisappear { stopRecording() }
    }

    private var displayLabel: String {
        if isRecording { return "Recording…" }
        if chord.isEmpty { return emptyLabel }
        return LeaderKeyBinding.parse(chord)?.displaySymbolString ?? chord
    }

    private var labelColor: Color {
        if isRecording { return ghosttyTheme.accent }
        if chord.isEmpty { return ghosttyTheme.tertiaryText }
        return ghosttyTheme.foreground
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape — cancel
                Task { @MainActor in stopRecording() }
                return nil
            }
            if event.keyCode == 51 || event.keyCode == 117 { // Delete / Forward Delete
                Task { @MainActor in
                    chord = ""
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

/// Click-to-record Normal-mode sequence (letters only, min 2, no `j`/`k`).
/// Esc cancels; Return commits; Delete clears last char (or clears when empty).
struct SequenceRecordField: View {
    @Binding var sequence: String
    /// Shown when unbound / empty.
    var emptyLabel: String = "—"
    /// Stretch to fill a table cell.
    var fillsWidth: Bool = false
    var onCommit: ((String) -> Void)?

    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme
    @State private var isRecording = false
    @State private var draft = ""
    @State private var monitor: Any?

    var body: some View {
        Button {
            if isRecording {
                commitDraft()
            } else {
                startRecording()
            }
        } label: {
            Text(displayLabel)
                .font(.body.monospaced())
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, fillsWidth ? 0 : 10)
                .padding(.vertical, fillsWidth ? 2 : 5)
                .background(fillsWidth ? Color.clear : ghosttyTheme.control)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            isRecording ? ghosttyTheme.accent : Color.clear,
                            lineWidth: 1.5
                        )
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        .help(
            isRecording
                ? "Type a sequence… (Return to save, Esc to cancel)"
                : "Click to record sequence"
        )
        .onDisappear { stopRecording(commit: false) }
    }

    private var displayLabel: String {
        if isRecording {
            return draft.isEmpty ? "Type…" : draft
        }
        if sequence.isEmpty { return emptyLabel }
        return sequence
    }

    private var labelColor: Color {
        if isRecording { return ghosttyTheme.accent }
        if sequence.isEmpty { return ghosttyTheme.tertiaryText }
        return ghosttyTheme.foreground
    }

    private func startRecording() {
        stopRecording(commit: false)
        draft = ""
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                Task { @MainActor in stopRecording(commit: false) }
                return nil
            }
            if event.keyCode == 36 || event.keyCode == 76 {
                Task { @MainActor in commitDraft() }
                return nil
            }
            if event.keyCode == 51 || event.keyCode == 117 {
                Task { @MainActor in
                    if draft.isEmpty {
                        apply("")
                        stopRecording(commit: false)
                    } else {
                        draft.removeLast()
                    }
                }
                return nil
            }

            guard let chars = event.charactersIgnoringModifiers?.lowercased(),
                  chars.count == 1,
                  let ch = chars.first,
                  ch.isLetter
            else { return nil }

            if CommandSequence.reserved.contains(ch) { return nil }

            Task { @MainActor in
                draft.append(ch)
                let sanitized = CommandSequence.sanitize(draft)
                if CommandSequence.isValid(sanitized) {
                    apply(sanitized)
                    stopRecording(commit: false)
                }
            }
            return nil
        }
    }

    private func commitDraft() {
        let sanitized = CommandSequence.sanitize(draft)
        if sanitized.isEmpty {
            apply("")
        } else if CommandSequence.isValid(sanitized) {
            apply(sanitized)
        }
        stopRecording(commit: false)
    }

    private func apply(_ value: String) {
        sequence = value
        onCommit?(value)
    }

    private func stopRecording(commit: Bool) {
        if commit {
            commitDraft()
            return
        }
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
        draft = ""
    }
}

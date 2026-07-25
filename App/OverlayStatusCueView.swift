import SwiftUI

/// Toggleable calm Status Cue: Editor + Background count → open/resume Overlay (C.7).
///
/// Lives in the status strip only — never a third column / switcher (nest is).
struct OverlayStatusCueView: View {
    @EnvironmentObject private var overlays: OverlayController
    @AppStorage(StatusCueDefaults.listVisibleKey) private var listVisible = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                listVisible.toggle()
            } label: {
                Image(systemName: "list.bullet")
                    .font(.caption)
                    .foregroundStyle(listVisible ? Color.secondary : Color.secondary.opacity(0.45))
            }
            .buttonStyle(.plain)
            .help(listVisible ? "Hide status cue" : "Show status cue")
            .accessibilityLabel(listVisible ? "Hide status cue" : "Show status cue")

            if listVisible {
                cueList
            }
        }
    }

    @ViewBuilder
    private var cueList: some View {
        HStack(spacing: 10) {
            editorRow

            let bgCount = overlays.focusedBackgroundCount
            if bgCount > 0 {
                backgroundRow(count: bgCount)
            }

            if overlays.isShowingOverlay, let visible = overlays.visibleSession {
                Text(visible.kind == .editor ? "peek · EDITOR" : "peek · BG")
                    .font(.caption2.weight(.medium).monospaced())
                    .foregroundStyle(.secondary)
                    .help("Overlay visible — Back / nest hide returns to Main CLI")
                    .accessibilityLabel("Peeking \(visible.kind == .editor ? "editor" : "background")")
            }
        }
    }

    private var editorRow: some View {
        let editor = overlays.focusedEditor
        let isLive = editor.map { overlays.visibleOverlayID == $0.id } ?? false
        return Button {
            overlays.peekOrOpenEditor()
        } label: {
            HStack(spacing: 3) {
                if isLive {
                    Circle()
                        .fill(Color.secondary.opacity(0.7))
                        .frame(width: 5, height: 5)
                }
                Text("editor")
                    .font(.caption2)
                    .foregroundStyle(editor == nil ? .tertiary : (isLive ? .secondary : .tertiary))
            }
        }
        .buttonStyle(.plain)
        .help(editor == nil ? "Open Editor Overlay" : "Peek Editor Overlay")
        .accessibilityLabel(editor == nil ? "Open editor" : "Peek editor")
    }

    private func backgroundRow(count: Int) -> some View {
        let visibleBG = overlays.visibleSession?.kind == .background
        return Button {
            overlays.peekPrimaryBackground()
        } label: {
            HStack(spacing: 3) {
                if visibleBG {
                    Circle()
                        .fill(Color.secondary.opacity(0.7))
                        .frame(width: 5, height: 5)
                }
                Text("· \(count)")
                    .font(.caption2)
                    .foregroundStyle(visibleBG ? .secondary : .tertiary)
                    .monospacedDigit()
            }
        }
        .buttonStyle(.plain)
        .help(count == 1
            ? "Peek Background CLI"
            : "Peek latest Background CLI (\(count) running) — Command Center nest to pick")
        .accessibilityLabel("\(count) background CLIs")
    }
}

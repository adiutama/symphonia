import AppKit
import SwiftUI

/// AppKit island that will later host libghostty render state.
/// Phase 0: visible placeholder only — no PTY, no libghostty.
final class TerminalSurfaceNSView: NSView {
    private let placeholderLabel = NSTextField(labelWithString: "Terminal surface")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1

        placeholderLabel.font = .systemFont(ofSize: 13, weight: .medium)
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.alignment = .center
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            placeholderLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// SwiftUI bridge for the AppKit terminal island (ADR 0011).
struct TerminalSurfaceView: NSViewRepresentable {
    func makeNSView(context: Context) -> TerminalSurfaceNSView {
        TerminalSurfaceNSView(frame: .zero)
    }

    func updateNSView(_ nsView: TerminalSurfaceNSView, context: Context) {}
}

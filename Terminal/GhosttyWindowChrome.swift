import AppKit
import SwiftUI

/// Applies Ghostty chrome colors to the hosting `NSWindow` (titlebar / window bg)
/// so macOS chrome blends with the terminal the way Ghostty does.
struct GhosttyWindowChrome: NSViewRepresentable {
    let background: NSColor
    let isDark: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            Self.apply(to: view.window, background: background, isDark: isDark)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            Self.apply(to: nsView.window, background: background, isDark: isDark)
        }
    }

    private static func apply(to window: NSWindow?, background: NSColor, isDark: Bool) {
        guard let window else { return }
        window.backgroundColor = background
        window.isOpaque = true
        // Full-size content + transparent titlebar: titlebar paints with the same
        // Ghostty background as the terminal (Ghostty-style blend).
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }
}

extension View {
    /// Tint the macOS window chrome to match Ghostty background / scheme.
    func ghosttyWindowChrome(_ theme: GhosttyChromeTheme) -> some View {
        background(
            GhosttyWindowChrome(
                background: theme.nsBackground,
                isDark: theme.colorScheme == .dark
            )
        )
    }
}

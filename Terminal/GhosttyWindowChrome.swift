import AppKit
import SwiftUI

/// Applies Ghostty chrome colors to the hosting `NSWindow` (titlebar / window bg)
/// so macOS chrome blends with the terminal the way Ghostty does.
///
/// Headless-ish: transparent titlebar + hidden title, system traffic lights kept.
/// Drag via chrome-only regions (`WindowDragRegion`) — not whole-window background.
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
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        // Never move the window from terminal / list hits — chrome drag regions only.
        window.isMovableByWindowBackground = false
        window.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }
}

/// Empty chrome that starts a window drag (status bar / sidebar header gaps).
/// Do not place over the terminal or interactive controls.
struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowDragNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowDragNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Participate in hit testing so empty chrome can drag; SwiftUI buttons
        // layered above still win their own frames.
        self
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

    /// Mark empty chrome as a window-drag surface (not for terminal / controls).
    func windowDragRegion() -> some View {
        background(WindowDragRegion())
    }
}

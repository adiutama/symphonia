import AppKit
import SwiftUI

/// Applies Ghostty chrome colors to the hosting `NSWindow` (titlebar / window bg)
/// so macOS chrome blends with the terminal the way Ghostty does.
///
/// Unified transparent titlebar + real toolbar items (from SwiftUI) so traffic lights
/// sit mid-band with our controls. Sidebar glass paints under via fullSizeContentView.
struct GhosttyWindowChrome: NSViewRepresentable {
    let background: NSColor
    let isDark: Bool
    /// When true, window is non-opaque so `NSVisualEffectView` blur can sample behind the window.
    var glass: Bool = false

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            Self.apply(to: view.window, background: background, isDark: isDark, glass: glass)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            Self.apply(to: nsView.window, background: background, isDark: isDark, glass: glass)
        }
    }

    private static func apply(to window: NSWindow?, background: NSColor, isDark: Bool, glass: Bool) {
        guard let window else { return }
        if glass {
            window.isOpaque = false
            window.backgroundColor = .clear
        } else {
            window.isOpaque = true
            window.backgroundColor = background
        }
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        if let toolbar = window.toolbar {
            toolbar.showsBaselineSeparator = false
            toolbar.isVisible = true
        }
        // Never move the window from terminal / list hits — chrome drag regions only.
        window.isMovableByWindowBackground = false
        window.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }
}

/// Empty chrome that starts a window drag (sidebar header gaps).
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
    /// Pass `glass: true` so sidebar / host visual-effect blur can sample the desktop.
    func ghosttyWindowChrome(_ theme: GhosttyChromeTheme, glass: Bool = false) -> some View {
        background(
            GhosttyWindowChrome(
                background: theme.nsBackground,
                isDark: theme.colorScheme == .dark,
                glass: glass
            )
        )
    }

    /// Mark empty chrome as a window-drag surface (not for terminal / controls).
    func windowDragRegion() -> some View {
        background(WindowDragRegion())
    }

    /// Transparent unified titlebar chrome. Pair with `.windowToolbarStyle(.unified)`
    /// and real `.toolbar` items so traffic lights align with controls.
    @ViewBuilder
    func symphoniaTitlebarChrome() -> some View {
        if #available(macOS 15.0, *) {
            self
                .toolbar(removing: .title)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            self
                .toolbarBackground(.hidden, for: .windowToolbar)
        }
    }
}

/// Forces Settings / preference windows into the Raycast–Supacode chrome:
/// transparent titlebar + full-size content so traffic lights sit over the sidebar.
struct SettingsWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            Self.apply(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            Self.apply(to: nsView.window)
        }
    }

    private static func apply(to window: NSWindow?) {
        guard let window else { return }
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = false
        // Settings scenes sometimes restore a visible toolbar; keep it empty/hidden.
        if let toolbar = window.toolbar {
            toolbar.isVisible = false
        }
    }
}

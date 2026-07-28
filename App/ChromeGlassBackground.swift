import AppKit
import SwiftUI

/// Frosted / Liquid Glass chrome background.
///
/// - macOS 26+: `NSGlassEffectView` (Liquid Glass) tinted toward Ghostty chrome colors
/// - earlier: `NSVisualEffectView` vibrancy (Sequence C fallback)
struct ChromeGlassBackground: NSViewRepresentable {
    var tintColor: NSColor?
    var cornerRadius: CGFloat = 0
    /// Used only on pre–Liquid Glass macOS.
    var fallbackMaterial: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    static var supportsLiquidGlass: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = cornerRadius
            glass.tintColor = tintColor
            glass.autoresizingMask = [.width, .height]
            return glass
        }
        let view = NSVisualEffectView()
        view.material = fallbackMaterial
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if #available(macOS 26.0, *), let glass = nsView as? NSGlassEffectView {
            glass.style = .regular
            glass.cornerRadius = cornerRadius
            glass.tintColor = tintColor
            return
        }
        guard let view = nsView as? NSVisualEffectView else { return }
        view.material = fallbackMaterial
        view.blendingMode = blendingMode
        view.state = state
    }
}

extension View {
    /// Full-bleed rail / pane glass + Ghostty tint when enabled; solid fill when off.
    @ViewBuilder
    func chromeSurface(
        glass: Bool,
        solid: Color,
        tintOpacity: Double = 0.22,
        material: NSVisualEffectView.Material = .hudWindow,
        cornerRadius: CGFloat = 0
    ) -> some View {
        if glass {
            background {
                ZStack {
                    ChromeGlassBackground(
                        tintColor: NSColor(solid).withAlphaComponent(
                            ChromeGlassBackground.supportsLiquidGlass ? 0.55 : 1
                        ),
                        cornerRadius: cornerRadius,
                        fallbackMaterial: material
                    )
                    // Vibrancy still needs a light Ghostty veil; Liquid Glass tint is enough
                    // once the window behind the rail is clear.
                    if !ChromeGlassBackground.supportsLiquidGlass {
                        solid.opacity(tintOpacity)
                    }
                }
            }
        } else {
            background(solid)
        }
    }

    /// Floating panel (Command Center / Overlay peek) — Liquid Glass on macOS 26+, solid otherwise.
    @ViewBuilder
    func chromeFloatingSurface(
        glass: Bool,
        solid: Color,
        cornerRadius: CGFloat
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if glass, #available(macOS 26.0, *) {
            self
                .background(solid.opacity(0.18), in: shape)
                .glassEffect(.regular.tint(solid.opacity(0.45)), in: shape)
                .clipShape(shape)
        } else if glass {
            self
                .background {
                    ZStack {
                        ChromeGlassBackground(
                            tintColor: NSColor(solid),
                            cornerRadius: cornerRadius,
                            fallbackMaterial: .hudWindow
                        )
                        solid.opacity(0.55)
                    }
                }
                .clipShape(shape)
        } else {
            self
                .background(solid, in: shape)
                .clipShape(shape)
        }
    }
}

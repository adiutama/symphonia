import AppKit
import SwiftUI

/// Liquid Glass chrome background (`NSGlassEffectView`), tinted toward Ghostty chrome colors.
struct ChromeGlassBackground: NSViewRepresentable {
    var tintColor: NSColor?
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = cornerRadius
        glass.tintColor = tintColor
        glass.autoresizingMask = [.width, .height]
        return glass
    }

    func updateNSView(_ glass: NSGlassEffectView, context: Context) {
        glass.style = .regular
        glass.cornerRadius = cornerRadius
        glass.tintColor = tintColor
    }
}

extension View {
    /// Full-bleed rail / pane glass + Ghostty tint when enabled; solid fill when off.
    @ViewBuilder
    func chromeSurface(
        glass: Bool,
        solid: Color,
        cornerRadius: CGFloat = 0
    ) -> some View {
        if glass {
            background {
                ChromeGlassBackground(
                    tintColor: NSColor(solid).withAlphaComponent(0.55),
                    cornerRadius: cornerRadius
                )
            }
        } else {
            background(solid)
        }
    }

    /// Floating panel (Command Center / Overlay peek) — Liquid Glass when enabled, solid otherwise.
    @ViewBuilder
    func chromeFloatingSurface(
        glass: Bool,
        solid: Color,
        cornerRadius: CGFloat
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if glass {
            self
                .background(solid.opacity(0.18), in: shape)
                .glassEffect(.regular.tint(solid.opacity(0.45)), in: shape)
                .clipShape(shape)
        } else {
            self
                .background(solid, in: shape)
                .clipShape(shape)
        }
    }
}

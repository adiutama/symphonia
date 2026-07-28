import AppKit
import SwiftUI

/// Frosted glass via `NSVisualEffectView` for sidebar / light window chrome.
struct ChromeGlassBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

extension View {
    /// Glass + Ghostty tint when enabled; solid fill when off.
    /// Lower `tintOpacity` → stronger frost / more desktop bleed.
    @ViewBuilder
    func chromeSurface(
        glass: Bool,
        solid: Color,
        tintOpacity: Double = 0.22,
        material: NSVisualEffectView.Material = .hudWindow
    ) -> some View {
        if glass {
            background {
                ZStack {
                    ChromeGlassBackground(material: material)
                    solid.opacity(tintOpacity)
                }
            }
        } else {
            background(solid)
        }
    }
}

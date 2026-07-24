import AppKit
import GhosttyKit
import SwiftUI

/// Chrome colors resolved from the Operator’s Ghostty config (same files terminals load).
///
/// Loads once at launch via `ghostty_config_load_default_files`. After changing Ghostty’s
/// theme, restart Symphonia to pick up new colors.
final class GhosttyChromeTheme: ObservableObject {
    let background: Color
    let foreground: Color
    /// Slightly elevated from background for sidebar / rail separation.
    let sidebar: Color
    /// Slightly elevated for the status bar strip.
    let bar: Color
    /// Solid panel fill for Command Center (avoids light system materials on dark themes).
    let panel: Color
    let colorScheme: ColorScheme
    /// AppKit placeholder behind a terminal surface before Ghostty paints.
    let nsBackground: NSColor

    static let shared = GhosttyChromeTheme()

    private init() {
        GhosttyBootstrap.ensureInitialized()
        let resolved = Self.loadFromGhosttyConfig()
        background = Color(nsColor: resolved.background)
        foreground = Color(nsColor: resolved.foreground)
        // Keep sidebar/bar on the exact Ghostty background so chrome blends with the
        // terminal (Ghostty-style). Hierarchy comes from list density / focus wash, not a second paint.
        sidebar = Color(nsColor: resolved.background)
        bar = Color(nsColor: resolved.background)
        // Command Center / Overlay chrome: tiny lift so panels read as peeks, not a different theme.
        panel = Color(nsColor: resolved.mix(toward: resolved.foreground, amount: 0.04))
        colorScheme = resolved.isDark ? .dark : .light
        nsBackground = resolved.background
    }

    private struct Resolved {
        var background: NSColor
        var foreground: NSColor

        var isDark: Bool {
            // Relative luminance (sRGB approx); Ghostty window-theme=auto uses the same idea.
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            background.usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
            let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
            return luminance < 0.45
        }

        func mix(toward other: NSColor, amount: CGFloat) -> NSColor {
            let t = min(max(amount, 0), 1)
            var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
            var orr: CGFloat = 0, og: CGFloat = 0, ob: CGFloat = 0, oa: CGFloat = 0
            let base = background.usingColorSpace(.sRGB) ?? background
            let tip = other.usingColorSpace(.sRGB) ?? other
            base.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
            tip.getRed(&orr, green: &og, blue: &ob, alpha: &oa)
            return NSColor(
                srgbRed: br + (orr - br) * t,
                green: bg + (og - bg) * t,
                blue: bb + (ob - bb) * t,
                alpha: 1
            )
        }
    }

    private static func loadFromGhosttyConfig() -> Resolved {
        let fallback = Resolved(
            background: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
            foreground: NSColor(srgbRed: 0.9, green: 0.9, blue: 0.9, alpha: 1)
        )

        guard let config = ghostty_config_new() else {
            return fallback
        }
        defer { ghostty_config_free(config) }

        ghostty_config_load_default_files(config)
        ghostty_config_finalize(config)

        var background = ghostty_config_color_s(r: 0, g: 0, b: 0)
        var foreground = ghostty_config_color_s(r: 230, g: 230, b: 230)

        let bgKey = "background"
        let fgKey = "foreground"
        _ = bgKey.withCString { keyPtr in
            ghostty_config_get(config, &background, keyPtr, UInt(bgKey.utf8.count))
        }
        _ = fgKey.withCString { keyPtr in
            ghostty_config_get(config, &foreground, keyPtr, UInt(fgKey.utf8.count))
        }

        return Resolved(
            background: NSColor(
                srgbRed: CGFloat(background.r) / 255,
                green: CGFloat(background.g) / 255,
                blue: CGFloat(background.b) / 255,
                alpha: 1
            ),
            foreground: NSColor(
                srgbRed: CGFloat(foreground.r) / 255,
                green: CGFloat(foreground.g) / 255,
                blue: CGFloat(foreground.b) / 255,
                alpha: 1
            )
        )
    }
}

/// One-time `ghostty_init` for the process (shared by chrome theme + terminal surfaces).
enum GhosttyBootstrap {
    private static var didInit = false

    static func ensureInitialized() {
        guard !didInit else { return }
        didInit = true
        let result = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        if result != GHOSTTY_SUCCESS {
            NSLog("ghostty_init failed with code \(result)")
        }
    }
}

import AppKit
import GhosttyKit
import SwiftUI

/// Chrome colors resolved from the Operator’s Ghostty config (same files terminals load).
///
/// Watches Ghostty config paths and reloads on change (and when the app becomes active)
/// so chrome stays in sync without restarting Symphonia.
final class GhosttyChromeTheme: ObservableObject {
    @Published private(set) var background: Color
    @Published private(set) var foreground: Color
    /// Darker than terminal background so the rail reads as chrome without washing out text.
    @Published private(set) var sidebar: Color
    /// Solid panel fill for Command Center / Settings cards (avoids light system materials).
    @Published private(set) var panel: Color
    /// Elevated fill for text fields / chord chips so controls read against `panel`.
    @Published private(set) var control: Color
    /// Accent from Ghostty palette index 4 (ANSI blue), used for tint / selection.
    @Published private(set) var accent: Color
    /// Subtle edge / divider stroke — solid fg mix (not alpha) so hairlines stay even over opaque chrome.
    @Published private(set) var hairline: Color
    /// Muted copy on Ghostty-filled chrome (replaces `.secondary`).
    @Published private(set) var secondaryText: Color
    /// Quieter chrome labels / placeholders (replaces `.tertiary`).
    @Published private(set) var tertiaryText: Color
    /// Selection wash for sidebar rows / Command Center items.
    @Published private(set) var selectionFill: Color
    @Published private(set) var colorScheme: ColorScheme
    /// AppKit placeholder behind a terminal surface before Ghostty paints.
    @Published private(set) var nsBackground: NSColor

    static let shared = GhosttyChromeTheme()

    private var sources: [DispatchSourceFileSystemObject] = []
    private var watchedDescriptors: [CInt] = []
    private var reloadWorkItem: DispatchWorkItem?
    private var becomeActiveObserver: NSObjectProtocol?

    private init() {
        GhosttyBootstrap.ensureInitialized()
        let resolved = Self.loadFromGhosttyConfig()
        let applied = Self.colors(from: resolved)
        background = applied.background
        foreground = applied.foreground
        sidebar = applied.sidebar
        panel = applied.panel
        control = applied.control
        accent = applied.accent
        hairline = applied.hairline
        secondaryText = applied.secondaryText
        tertiaryText = applied.tertiaryText
        selectionFill = applied.selectionFill
        colorScheme = applied.colorScheme
        nsBackground = applied.nsBackground

        startWatchingConfigFiles()
        becomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Defer past any in-flight SwiftUI AttributeGraph update.
            DispatchQueue.main.async { [weak self] in
                self?.reload()
            }
        }
    }

    deinit {
        stopWatching()
        if let becomeActiveObserver {
            NotificationCenter.default.removeObserver(becomeActiveObserver)
        }
    }

    /// Re-read Ghostty config and publish updated chrome colors.
    func reload() {
        GhosttyBootstrap.ensureInitialized()
        let resolved = Self.loadFromGhosttyConfig()
        apply(resolved)
    }

    private func scheduleReload() {
        reloadWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.reload()
            // Editors often replace config atomically (unlink + create); re-arm watches.
            self?.startWatchingConfigFiles()
        }
        reloadWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func apply(_ resolved: Resolved) {
        let applied = Self.colors(from: resolved)
        background = applied.background
        foreground = applied.foreground
        sidebar = applied.sidebar
        panel = applied.panel
        control = applied.control
        accent = applied.accent
        hairline = applied.hairline
        secondaryText = applied.secondaryText
        tertiaryText = applied.tertiaryText
        selectionFill = applied.selectionFill
        colorScheme = applied.colorScheme
        nsBackground = applied.nsBackground
    }

    private struct AppliedColors {
        var background: Color
        var foreground: Color
        var sidebar: Color
        var panel: Color
        var control: Color
        var accent: Color
        var hairline: Color
        var secondaryText: Color
        var tertiaryText: Color
        var selectionFill: Color
        var colorScheme: ColorScheme
        var nsBackground: NSColor
    }

    private static func colors(from resolved: Resolved) -> AppliedColors {
        let accentColor = Color(nsColor: resolved.accent)
        // Sidebar goes darker than the Ghostty terminal bg (Catppuccin crust/mantle idea):
        // lightening the rail washed out muted themes and hurt text contrast.
        // Panels/controls still lift lighter so cards/fields read above the canvas.
        let sidebarBase = resolved.mix(toward: NSColor.black, amount: resolved.isDark ? 0.28 : 0.08)
        let panelLift = resolved.mix(toward: resolved.foreground, amount: 0.10)
        return AppliedColors(
            background: Color(nsColor: resolved.background),
            foreground: Color(nsColor: resolved.foreground),
            sidebar: Color(nsColor: Resolved.mix(sidebarBase, toward: resolved.accent, amount: 0.06)),
            panel: Color(nsColor: Resolved.mix(panelLift, toward: resolved.accent, amount: 0.05)),
            control: Color(nsColor: resolved.mix(toward: resolved.foreground, amount: 0.20)),
            accent: accentColor,
            hairline: Color(nsColor: resolved.mix(toward: resolved.foreground, amount: 0.20)),
            // Keep muted labels closer to fg so they stay readable on the darker rail.
            secondaryText: Color(nsColor: resolved.mix(toward: resolved.foreground, amount: 0.72)),
            tertiaryText: Color(nsColor: resolved.mix(toward: resolved.foreground, amount: 0.50)),
            selectionFill: accentColor.opacity(0.28),
            colorScheme: resolved.isDark ? .dark : .light,
            nsBackground: resolved.background
        )
    }


    // MARK: - Config path watching

    private func startWatchingConfigFiles() {
        stopWatching()
        let paths = Self.ghosttyConfigPaths()
        for path in paths {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            watchedDescriptors.append(fd)
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .delete, .extend, .attrib],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                self?.scheduleReload()
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()
            sources.append(source)
        }
    }

    private func stopWatching() {
        for source in sources {
            source.cancel()
        }
        sources.removeAll()
        // Descriptors are closed in each source's cancel handler.
        watchedDescriptors.removeAll()
    }

    /// Paths Ghostty typically loads on macOS (same family as `ghostty_config_load_default_files`).
    private static func ghosttyConfigPaths() -> [String] {
        var paths: [String] = []
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/Library/Application Support/com.mitchellh.ghostty/config",
            "\(home)/Library/Application Support/com.mitchellh.ghostty/config.ghostty",
            "\(home)/.config/ghostty/config",
            "\(home)/.config/ghostty/config.ghostty",
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                paths.append(path)
            }
        }
        // Always watch parent dirs that exist so a newly created config still triggers.
        let dirs = [
            "\(home)/Library/Application Support/com.mitchellh.ghostty",
            "\(home)/.config/ghostty",
        ]
        for dir in dirs where FileManager.default.fileExists(atPath: dir) {
            if !paths.contains(dir) {
                paths.append(dir)
            }
        }
        return paths
    }

    private struct Resolved {
        var background: NSColor
        var foreground: NSColor
        /// ANSI blue (palette 4), or a mid mix when palette is unavailable.
        var accent: NSColor

        var isDark: Bool {
            // Relative luminance (sRGB approx); Ghostty window-theme=auto uses the same idea.
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            background.usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
            let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
            return luminance < 0.45
        }

        func mix(toward other: NSColor, amount: CGFloat) -> NSColor {
            Self.mix(background, toward: other, amount: amount)
        }

        static func mix(_ baseColor: NSColor, toward other: NSColor, amount: CGFloat) -> NSColor {
            let t = min(max(amount, 0), 1)
            var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
            var orr: CGFloat = 0, og: CGFloat = 0, ob: CGFloat = 0, oa: CGFloat = 0
            let base = baseColor.usingColorSpace(.sRGB) ?? baseColor
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
        let fallbackForeground = NSColor(srgbRed: 0.9, green: 0.9, blue: 0.9, alpha: 1)
        let fallbackBackground = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let fallback = Resolved(
            background: fallbackBackground,
            foreground: fallbackForeground,
            accent: NSColor(srgbRed: 0.45, green: 0.55, blue: 0.85, alpha: 1)
        )

        guard let config = ghostty_config_new() else {
            return fallback
        }
        defer { ghostty_config_free(config) }

        ghostty_config_load_default_files(config)
        ghostty_config_finalize(config)

        var background = ghostty_config_color_s(r: 0, g: 0, b: 0)
        var foreground = ghostty_config_color_s(r: 230, g: 230, b: 230)
        var palette = ghostty_config_palette_s()

        let bgKey = "background"
        let fgKey = "foreground"
        let paletteKey = "palette"
        _ = bgKey.withCString { keyPtr in
            ghostty_config_get(config, &background, keyPtr, UInt(bgKey.utf8.count))
        }
        _ = fgKey.withCString { keyPtr in
            ghostty_config_get(config, &foreground, keyPtr, UInt(fgKey.utf8.count))
        }
        let gotPalette = paletteKey.withCString { keyPtr in
            ghostty_config_get(config, &palette, keyPtr, UInt(paletteKey.utf8.count))
        }

        let bg = Self.nsColor(from: background)
        let fg = Self.nsColor(from: foreground)
        let accent: NSColor
        if gotPalette {
            // Index 4 = ANSI blue — theme accent for chrome tint / selection.
            accent = withUnsafeBytes(of: palette.colors) { raw in
                let colors = raw.bindMemory(to: ghostty_config_color_s.self)
                return Self.nsColor(from: colors[4])
            }
        } else {
            accent = Resolved(background: bg, foreground: fg, accent: fallback.accent)
                .mix(toward: fg, amount: 0.55)
        }

        return Resolved(background: bg, foreground: fg, accent: accent)
    }

    private static func nsColor(from color: ghostty_config_color_s) -> NSColor {
        NSColor(
            srgbRed: CGFloat(color.r) / 255,
            green: CGFloat(color.g) / 255,
            blue: CGFloat(color.b) / 255,
            alpha: 1
        )
    }
}

/// One-time `ghostty_init` for the process (shared by chrome theme + terminal surfaces).
enum GhosttyBootstrap {
    private static var didInit = false

    static func ensureInitialized() {
        guard !didInit else { return }
        didInit = true
        Self.exportResourcesDirIfNeeded()
        let result = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        if result != GHOSTTY_SUCCESS {
            NSLog("ghostty_init failed with code \(result)")
        }
    }

    /// Point libghostty at a resources root that contains `themes/` (and usually
    /// `shell-integration/`). Prefer an already-set env, then optional bundled
    /// `Contents/Resources/ghostty`, then the installed Ghostty.app — so nightlies
    /// can honor `~/.config/ghostty` `theme = …` without shipping theme files.
    private static func exportResourcesDirIfNeeded() {
        if ProcessInfo.processInfo.environment["GHOSTTY_RESOURCES_DIR"] != nil { return }
        guard let resources = Self.resolveGhosttyResourcesDir() else {
            NSLog(
                "Ghostty resources not found — theme= in config will not resolve. Install Ghostty.app or set GHOSTTY_RESOURCES_DIR."
            )
            return
        }
        setenv("GHOSTTY_RESOURCES_DIR", resources, 0)
    }

    /// Directory that contains `themes/` (Ghostty’s `…/ghostty` resources root).
    private static func resolveGhosttyResourcesDir() -> String? {
        let fm = FileManager.default

        // Optional: themes copied into Symphonia.app (local/dev packaging).
        if let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("ghostty", isDirectory: true)
            .path,
            fm.fileExists(atPath: (bundled as NSString).appendingPathComponent("themes"))
        {
            return bundled
        }

        // Installed Ghostty client — same themes the Operator’s config refers to.
        for appURL in Self.ghosttyAppURLs() {
            let candidate = appURL
                .appendingPathComponent("Contents/Resources/ghostty", isDirectory: true)
                .path
            if fm.fileExists(atPath: (candidate as NSString).appendingPathComponent("themes")) {
                return candidate
            }
        }

        return nil
    }

    /// Likely Ghostty.app locations (bundle-id lookup, then common install dirs).
    private static func ghosttyAppURLs() -> [URL] {
        var urls: [URL] = []
        let fm = FileManager.default

        if let running = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.mitchellh.ghostty"
        ) {
            urls.append(running)
        }

        let home = fm.homeDirectoryForCurrentUser
        let fallbacks = [
            URL(fileURLWithPath: "/Applications/Ghostty.app", isDirectory: true),
            home.appendingPathComponent("Applications/Ghostty.app", isDirectory: true),
        ]
        for url in fallbacks where fm.fileExists(atPath: url.path) {
            if !urls.contains(url) {
                urls.append(url)
            }
        }
        return urls
    }
}

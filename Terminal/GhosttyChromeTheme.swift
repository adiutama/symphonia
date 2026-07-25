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
    /// Slightly elevated from background for sidebar / rail separation.
    @Published private(set) var sidebar: Color
    /// Slightly elevated for the status bar strip.
    @Published private(set) var bar: Color
    /// Solid panel fill for Command Center (avoids light system materials on dark themes).
    @Published private(set) var panel: Color
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
        bar = applied.bar
        panel = applied.panel
        colorScheme = applied.colorScheme
        nsBackground = applied.nsBackground

        startWatchingConfigFiles()
        becomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reload()
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
        bar = applied.bar
        panel = applied.panel
        colorScheme = applied.colorScheme
        nsBackground = applied.nsBackground
    }

    private struct AppliedColors {
        var background: Color
        var foreground: Color
        var sidebar: Color
        var bar: Color
        var panel: Color
        var colorScheme: ColorScheme
        var nsBackground: NSColor
    }

    private static func colors(from resolved: Resolved) -> AppliedColors {
        AppliedColors(
            background: Color(nsColor: resolved.background),
            foreground: Color(nsColor: resolved.foreground),
            // Sidebar lifts off the Ghostty terminal background so the traffic-light column
            // reads as its own surface (Xcode / Raycast). Bar stays on background.
            sidebar: Color(nsColor: resolved.mix(toward: resolved.foreground, amount: 0.07)),
            bar: Color(nsColor: resolved.background),
            // Command Center / Overlay chrome: tiny lift so panels read as peeks, not a different theme.
            panel: Color(nsColor: resolved.mix(toward: resolved.foreground, amount: 0.04)),
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
        Self.exportResourcesDirIfNeeded()
        let result = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        if result != GHOSTTY_SUCCESS {
            NSLog("ghostty_init failed with code \(result)")
        }
    }

    /// Point libghostty at bundled themes (`Contents/Resources/ghostty`) when present.
    /// Terminfo under Resources is the primary discovery path; this env is a Debug fallback.
    private static func exportResourcesDirIfNeeded() {
        if ProcessInfo.processInfo.environment["GHOSTTY_RESOURCES_DIR"] != nil { return }
        guard let resources = Bundle.main.resourceURL?
            .appendingPathComponent("ghostty", isDirectory: true)
            .path,
            FileManager.default.fileExists(atPath: resources)
        else { return }
        setenv("GHOSTTY_RESOURCES_DIR", resources, 0)
    }
}

import AppKit
import GhosttyKit
import SwiftUI

/// Owns one Ghostty app + surface bound to this `NSView` (ADR 0011).
///
/// P1.1: render surface only. Ghostty may still start its default shell internally;
/// Symphonia-owned PTY / session lifecycle is deferred to P1.2.
final class TerminalSurfaceNSView: NSView {
    private var ghosttyApp: ghostty_app_t?
    private var ghosttyConfig: ghostty_config_t?
    private var surface: ghostty_surface_t?
    private var statusLabel: NSTextField?
    private var didStart = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        tearDownGhostty()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !didStart else { return }
        didStart = true
        startGhostty()
    }

    override func layout() {
        super.layout()
        syncSurfaceGeometry()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncSurfaceGeometry()
    }

    // MARK: - Ghostty lifecycle

    private func startGhostty() {
        GhosttyBootstrap.ensureInitialized()

        guard let config = ghostty_config_new() else {
            showStatus("ghostty_config_new failed")
            return
        }
        ghostty_config_load_default_files(config)
        ghostty_config_finalize(config)
        ghosttyConfig = config

        var runtime = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            supports_selection_clipboard: true,
            wakeup_cb: { userdata in
                guard let userdata else { return }
                let view = Unmanaged<TerminalSurfaceNSView>.fromOpaque(userdata).takeUnretainedValue()
                DispatchQueue.main.async {
                    view.tick()
                }
            },
            action_cb: { _, _, _ in false },
            read_clipboard_cb: { _, _, _ in false },
            confirm_read_clipboard_cb: { _, _, _, _ in },
            write_clipboard_cb: { _, _, _, _, _ in },
            close_surface_cb: { userdata, _ in
                guard let userdata else { return }
                let view = Unmanaged<TerminalSurfaceNSView>.fromOpaque(userdata).takeUnretainedValue()
                DispatchQueue.main.async {
                    view.handleSurfaceCloseRequest()
                }
            }
        )

        guard let app = ghostty_app_new(&runtime, config) else {
            showStatus("ghostty_app_new failed")
            return
        }
        ghosttyApp = app
        ghostty_app_set_focus(app, true)

        var surfaceConfig = ghostty_surface_config_new()
        surfaceConfig.userdata = Unmanaged.passUnretained(self).toOpaque()
        surfaceConfig.platform_tag = GHOSTTY_PLATFORM_MACOS
        surfaceConfig.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(
                nsview: Unmanaged.passUnretained(self).toOpaque()
            )
        )
        surfaceConfig.scale_factor = Double(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        surfaceConfig.font_size = 0 // inherit from config
        // P1.2: set `command` / env / working_directory from Symphonia session, or feed bytes via PTY APIs.
        surfaceConfig.wait_after_command = false
        surfaceConfig.context = GHOSTTY_SURFACE_CONTEXT_WINDOW

        guard let surface = ghostty_surface_new(app, &surfaceConfig) else {
            showStatus("ghostty_surface_new failed")
            return
        }
        self.surface = surface
        clearStatus()
        syncSurfaceGeometry()
        ghostty_surface_set_focus(surface, true)
        ghostty_surface_refresh(surface)
        tick()
    }

    private func tearDownGhostty() {
        if let surface {
            ghostty_surface_free(surface)
            self.surface = nil
        }
        if let app = ghosttyApp {
            ghostty_app_free(app)
            ghosttyApp = nil
        }
        if let config = ghosttyConfig {
            ghostty_config_free(config)
            ghosttyConfig = nil
        }
    }

    private func tick() {
        guard let app = ghosttyApp else { return }
        ghostty_app_tick(app)
    }

    private func syncSurfaceGeometry() {
        guard let surface else { return }
        let scale = Double(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        let width = UInt32(max(1, bounds.width.rounded(.down)))
        let height = UInt32(max(1, bounds.height.rounded(.down)))
        ghostty_surface_set_content_scale(surface, scale, scale)
        ghostty_surface_set_size(surface, width, height)
    }

    private func handleSurfaceCloseRequest() {
        // P1.2: map to Symphonia session teardown instead of freeing immediately if shared.
        tearDownGhostty()
        showStatus("Surface closed")
    }

    private func showStatus(_ message: String) {
        if statusLabel == nil {
            let label = NSTextField(labelWithString: message)
            label.font = .systemFont(ofSize: 13, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: centerXAnchor),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
            statusLabel = label
        } else {
            statusLabel?.stringValue = message
        }
    }

    private func clearStatus() {
        statusLabel?.removeFromSuperview()
        statusLabel = nil
    }
}

/// One-time `ghostty_init` for the process.
private enum GhosttyBootstrap {
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

/// SwiftUI bridge for the AppKit terminal island (ADR 0011).
struct TerminalSurfaceView: NSViewRepresentable {
    func makeNSView(context: Context) -> TerminalSurfaceNSView {
        TerminalSurfaceNSView(frame: .zero)
    }

    func updateNSView(_ nsView: TerminalSurfaceNSView, context: Context) {}
}

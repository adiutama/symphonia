import AppKit
import GhosttyKit
import QuartzCore

extension TerminalSurfaceNSView {
    // MARK: - Ghostty lifecycle

    func startGhostty() {
        GhosttyBootstrap.ensureInitialized()

        guard let config = ghostty_config_new() else {
            showStatus("ghostty_config_new failed")
            return
        }
        ghostty_config_load_default_files(config)
        ghostty_config_finalize(config)
        ghosttyConfig = config

        // false → default `copy-on-select = true` writes the *system* clipboard
        // (macOS has no X11-style selection clipboard; Ghostty's private pasteboard
        // made select-to-copy look broken for ⌘V / other apps).
        var runtime = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            supports_selection_clipboard: false,
            wakeup_cb: { userdata in
                guard let userdata else { return }
                let view = Unmanaged<TerminalSurfaceNSView>.fromOpaque(userdata).takeUnretainedValue()
                DispatchQueue.main.async {
                    view.tick()
                }
            },
            action_cb: { _, _, _ in false },
            read_clipboard_cb: { userdata, location, state in
                TerminalSurfaceNSView.readClipboard(userdata, location: location, state: state)
            },
            confirm_read_clipboard_cb: { userdata, string, state, request in
                TerminalSurfaceNSView.confirmReadClipboard(
                    userdata,
                    string: string,
                    state: state,
                    request: request
                )
            },
            write_clipboard_cb: { userdata, location, content, len, confirm in
                TerminalSurfaceNSView.writeClipboard(
                    userdata,
                    location: location,
                    content: content,
                    len: Int(len),
                    confirm: confirm
                )
            },
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
        // P4.5 / P5.3: Worktree cwd + Effective Main CLI + Enabled Secret Store env.
        releaseSpawnCStrings()
        if let workingDirectory {
            workingDirectoryCString = strdup(workingDirectory)
            surfaceConfig.working_directory = UnsafePointer(workingDirectoryCString)
        }
        if let command {
            commandCString = strdup(command)
            surfaceConfig.command = UnsafePointer(commandCString)
        }
        if !spawnEnvironment.isEmpty {
            var copied: [(key: UnsafeMutablePointer<CChar>, value: UnsafeMutablePointer<CChar>)] = []
            copied.reserveCapacity(spawnEnvironment.count)
            for pair in spawnEnvironment {
                let keyPtr = strdup(pair.key)
                let valuePtr = strdup(pair.value)
                guard let keyPtr, let valuePtr else {
                    assertionFailure("strdup failed for spawn environment")
                    if let keyPtr { free(keyPtr) }
                    if let valuePtr { free(valuePtr) }
                    break
                }
                copied.append((keyPtr, valuePtr))
                envKeyCStrings.append(keyPtr)
                envValueCStrings.append(valuePtr)
            }
            if !copied.isEmpty {
                let count = copied.count
                let buffer = UnsafeMutablePointer<ghostty_env_var_s>.allocate(capacity: count)
                envVarsBuffer = buffer
                for (index, pair) in copied.enumerated() {
                    buffer[index] = ghostty_env_var_s(key: pair.key, value: pair.value)
                }
                surfaceConfig.env_vars = buffer
                surfaceConfig.env_var_count = count
            }
        }
        surfaceConfig.wait_after_command = false
        surfaceConfig.context = GHOSTTY_SURFACE_CONTEXT_WINDOW

        guard let surface = ghostty_surface_new(app, &surfaceConfig) else {
            showStatus("ghostty_surface_new failed")
            return
        }
        self.surface = surface
        clearStatus()
        if let window {
            syncLayerContentsScale(for: window)
            syncDisplayID(for: window)
        }
        syncSurfaceGeometry()
        setSurfaceFocus(true)
        installLocalEventMonitor()
        ghostty_surface_refresh(surface)
        tick()
    }

    func tearDownGhostty() {
        removeLocalEventMonitor()
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
        releaseSpawnCStrings()
        surfaceFocused = false
    }

    private func releaseSpawnCStrings() {
        if let workingDirectoryCString {
            free(workingDirectoryCString)
            self.workingDirectoryCString = nil
        }
        if let commandCString {
            free(commandCString)
            self.commandCString = nil
        }
        for ptr in envKeyCStrings {
            free(ptr)
        }
        for ptr in envValueCStrings {
            free(ptr)
        }
        envKeyCStrings.removeAll(keepingCapacity: false)
        envValueCStrings.removeAll(keepingCapacity: false)
        if let envVarsBuffer {
            envVarsBuffer.deallocate()
            self.envVarsBuffer = nil
        }
    }

    private func tick() {
        guard let app = ghosttyApp else { return }
        ghostty_app_tick(app)
    }

    func syncSurfaceGeometry() {
        guard let surface else { return }
        // Ghostty expects framebuffer pixels (backing), not points — same as
        // SurfaceView_AppKit.sizeDidChange (`convertToBacking`). Passing points on
        // Retina leaves the Metal surface at ~½×½ of the view.
        let pointSize = bounds.size
        guard pointSize.width > 0, pointSize.height > 0 else { return }

        if let window {
            syncLayerContentsScale(for: window)
        }

        let backing = convertToBacking(NSRect(origin: .zero, size: pointSize)).size
        let scaleX = Double(backing.width / pointSize.width)
        let scaleY = Double(backing.height / pointSize.height)
        let width = UInt32(max(1, backing.width.rounded(.down)))
        let height = UInt32(max(1, backing.height.rounded(.down)))
        ghostty_surface_set_content_scale(surface, scaleX, scaleY)
        ghostty_surface_set_size(surface, width, height)
    }

    /// Keep CA layer scale in lockstep with the window so moving between Retina and
    /// external monitors does not leave the compositor stretching stale contents.
    func syncLayerContentsScale(for window: NSWindow) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contentsScale = window.backingScaleFactor
        CATransaction.commit()
    }

    func syncDisplayID(for window: NSWindow) {
        guard let surface, let screen = window.screen else { return }
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) ?? 0
        ghostty_surface_set_display_id(surface, displayID)
    }

    func installScreenObserver() {
        removeScreenObserver()
        guard let window else { return }
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self, let window = self.window else { return }
            // Match Ghostty: update display id for vsync, then re-run backing sync
            // asynchronously so scale/size settle after the screen change.
            self.syncDisplayID(for: window)
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                self.syncLayerContentsScale(for: window)
                self.syncSurfaceGeometry()
            }
        }
        syncDisplayID(for: window)
    }

    func removeScreenObserver() {
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
            self.screenChangeObserver = nil
        }
    }

    private func handleSurfaceCloseRequest() {
        tearDownGhostty()
        if let onProcessExit {
            onProcessExit()
        } else {
            showStatus("Surface closed")
        }
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

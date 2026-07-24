import AppKit
import GhosttyKit
import SwiftUI

/// Owns one Ghostty app + surface bound to this `NSView` (ADR 0011).
///
/// P1.1: render surface. P1.3: AppKit first-responder + key/mouse → `ghostty_surface_*`
/// (mirrors Ghostty's `SurfaceView_AppKit` / `NSEvent+Extension` patterns).
/// C.5: Ghostty ↔ NSPasteboard (select-to-copy, ⌘C/⌘V, right-click Copy/Paste).
/// C.6: scrollback enter reset, font zoom via bindings, click-to-focus without eating.
/// Symphonia-owned PTY / session lifecycle remains P1.2.
final class TerminalSurfaceNSView: NSView, NSMenuItemValidation {
    private var ghosttyApp: ghostty_app_t?
    private var ghosttyConfig: ghostty_config_t?
    private var surface: ghostty_surface_t?
    private var statusLabel: NSTextField?
    /// Ephemeral “Copied” / “Pasted” HUD (auto-dismiss).
    private var clipboardToastLabel: NSTextField?
    private var clipboardToastHideWorkItem: DispatchWorkItem?
    /// Local monitor: focus on left-click without eating the event (C.6).
    private var localEventMonitor: Any?
    private var didStart = false
    private var surfaceFocused = false

    /// Spawn config for Ghostty surface (P4.5 / P5.3). Empty command = bare shell / Ghostty default.
    private var workingDirectory: String?
    private var command: String?
    /// Enabled Secret Store Env Vars for this spawn (empty = no Secret Store inject).
    private var spawnEnvironment: [(key: String, value: String)] = []

    /// Retained C strings for `ghostty_surface_config_s` (must outlive `ghostty_surface_new`).
    private var workingDirectoryCString: UnsafeMutablePointer<CChar>?
    private var commandCString: UnsafeMutablePointer<CChar>?
    private var envKeyCStrings: [UnsafeMutablePointer<CChar>] = []
    private var envValueCStrings: [UnsafeMutablePointer<CChar>] = []
    private var envVarsBuffer: UnsafeMutablePointer<ghostty_env_var_s>?

    /// Accumulates `insertText` while handling `keyDown` via `interpretKeyEvents`
    /// (same pattern as Ghostty's SurfaceView).
    private var keyTextAccumulator: [String]?

    /// Observes window screen changes (Retina ↔ external) so we re-sync scale/size.
    private var screenChangeObserver: NSObjectProtocol?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = GhosttyChromeTheme.shared.nsBackground.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        tearDownGhostty()
        removeScreenObserver()
        removeLocalEventMonitor()
    }

    /// Apply spawn config; restart only when cwd / command / env actually change (not on show/hide).
    func applySpawnConfig(
        workingDirectory: String?,
        command: String?,
        spawnEnvironment: [(key: String, value: String)] = []
    ) {
        let cwdChanged = self.workingDirectory != workingDirectory
        let cmdChanged = self.command != command
        let envChanged = !Self.environmentEqual(self.spawnEnvironment, spawnEnvironment)
        guard cwdChanged || cmdChanged || envChanged else { return }

        self.workingDirectory = workingDirectory
        self.command = command
        self.spawnEnvironment = spawnEnvironment

        guard didStart, window != nil else { return }
        tearDownGhostty()
        startGhostty()
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }

    /// When this surface becomes the visible Main CLI / Overlay, take keyboard focus.
    func setActive(_ active: Bool) {
        guard window != nil else { return }
        if active {
            if window?.firstResponder !== self {
                window?.makeFirstResponder(self)
            } else {
                setSurfaceFocus(true)
            }
        } else {
            setSurfaceFocus(false)
        }
    }

    private static func environmentEqual(
        _ lhs: [(key: String, value: String)],
        _ rhs: [(key: String, value: String)]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (a, b) in zip(lhs, rhs) {
            if a.key != b.key || a.value != b.value { return false }
        }
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installScreenObserver()
        if let window {
            syncLayerContentsScale(for: window)
            syncDisplayID(for: window)
        }
        guard window != nil, !didStart else {
            // Window changed after start (e.g. moved) — still re-sync geometry.
            if didStart { syncSurfaceGeometry() }
            return
        }
        didStart = true
        startGhostty()
        // Become key once the window is ready so typing works without an extra click.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
            self.syncSurfaceGeometry()
        }
    }

    override func layout() {
        super.layout()
        syncSurfaceGeometry()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        // When moving Retina ↔ low-DPI, Core Animation scales the layer unless
        // contentsScale matches the window — Ghostty SurfaceView_AppKit does this.
        if let window {
            syncLayerContentsScale(for: window)
        }
        syncSurfaceGeometry()
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .inVisibleRect, .activeAlways],
            owner: self,
            userInfo: nil
        ))
    }

    // MARK: - First responder / focus

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { setSurfaceFocus(true) }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { setSurfaceFocus(false) }
        return ok
    }

    private func setSurfaceFocus(_ focused: Bool) {
        guard surfaceFocused != focused else { return }
        surfaceFocused = focused
        if let surface {
            ghostty_surface_set_focus(surface, focused)
        }
        if let app = ghosttyApp {
            ghostty_app_set_focus(app, focused)
        }
    }

    // MARK: - Keyboard (Ghostty SurfaceView_AppKit key path, slimmed)

    override func keyDown(with event: NSEvent) {
        guard let surface else {
            super.keyDown(with: event)
            return
        }

        // Option-as-alt / similar: translate mods the way Ghostty does before IME.
        let translationModsGhostty = GhosttyInput.eventModifierFlags(
            mods: ghostty_surface_key_translation_mods(
                surface,
                GhosttyInput.mods(event.modifierFlags)
            )
        )
        var translationMods = event.modifierFlags
        for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command] {
            if translationModsGhostty.contains(flag) {
                translationMods.insert(flag)
            } else {
                translationMods.remove(flag)
            }
        }

        let translationEvent: NSEvent
        if translationMods == event.modifierFlags {
            translationEvent = event
        } else {
            translationEvent = NSEvent.keyEvent(
                with: event.type,
                location: event.locationInWindow,
                modifierFlags: translationMods,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                characters: event.characters(byApplyingModifiers: translationMods) ?? "",
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                isARepeat: event.isARepeat,
                keyCode: event.keyCode
            ) ?? event
        }

        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }

        interpretKeyEvents([translationEvent])

        if let list = keyTextAccumulator, !list.isEmpty {
            for text in list {
                _ = sendKey(
                    action,
                    event: event,
                    translationMods: translationEvent.modifierFlags,
                    text: text
                )
            }
        } else {
            _ = sendKey(
                action,
                event: event,
                translationMods: translationEvent.modifierFlags,
                text: translationEvent.ghosttyCharacters
            )
        }
    }

    override func keyUp(with event: NSEvent) {
        _ = sendKey(GHOSTTY_ACTION_RELEASE, event: event)
    }

    override func flagsChanged(with event: NSEvent) {
        let mod: UInt32
        switch event.keyCode {
        case 0x39: mod = GHOSTTY_MODS_CAPS.rawValue
        case 0x38, 0x3C: mod = GHOSTTY_MODS_SHIFT.rawValue
        case 0x3B, 0x3E: mod = GHOSTTY_MODS_CTRL.rawValue
        case 0x3A, 0x3D: mod = GHOSTTY_MODS_ALT.rawValue
        case 0x37, 0x36: mod = GHOSTTY_MODS_SUPER.rawValue
        default: return
        }

        let mods = GhosttyInput.mods(event.modifierFlags)
        let action: ghostty_input_action_e =
            (mods.rawValue & mod) != 0 ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
        _ = sendKey(action, event: event)
    }

    /// `NSTextInputClient`-style insert during `interpretKeyEvents`.
    override func insertText(_ insertString: Any) {
        let chars: String
        switch insertString {
        case let v as NSAttributedString:
            chars = v.string
        case let v as String:
            chars = v
        default:
            return
        }
        if var acc = keyTextAccumulator {
            acc.append(chars)
            keyTextAccumulator = acc
            return
        }
        guard let surface, !chars.isEmpty else { return }
        chars.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(chars.utf8.count))
        }
    }

    override func doCommand(by selector: Selector) {
        // Swallow unimplemented editing commands so AppKit does not beep;
        // control keys still reach Ghostty via the keyDown fallthrough path
        // when `insertText` did not accumulate.
    }

    /// Route Ghostty keybindings (⌘C/V, ⌘+/−/0 font zoom, …) through `keyDown`
    /// before the Edit/View menu consumes them — same seam as Ghostty `SurfaceView_AppKit`.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        guard surfaceFocused, let surface else { return false }

        var ghosttyEvent = event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS)
        var flags = ghostty_binding_flags_e(0)
        let isBinding = (event.characters ?? "").withCString { ptr in
            ghosttyEvent.text = ptr
            return ghostty_surface_key_is_binding(surface, ghosttyEvent, &flags)
        }
        if isBinding {
            keyDown(with: event)
            return true
        }
        return false
    }

    @discardableResult
    private func sendKey(
        _ action: ghostty_input_action_e,
        event: NSEvent,
        translationMods: NSEvent.ModifierFlags? = nil,
        text: String? = nil
    ) -> Bool {
        guard let surface else { return false }

        var keyEvent = event.ghosttyKeyEvent(action, translationMods: translationMods)

        // Mirror Ghostty: only pass UTF-8 text for non-control characters;
        // Ghostty encodes control sequences from keycode + mods itself.
        if let text, !text.isEmpty,
           let codepoint = text.utf8.first, codepoint >= 0x20 {
            return text.withCString { ptr in
                keyEvent.text = ptr
                return ghostty_surface_key(surface, keyEvent)
            }
        }
        return ghostty_surface_key(surface, keyEvent)
    }

    // MARK: - Mouse (focus + report path)

    override func mouseDown(with event: NSEvent) {
        // Focus is owned by the local leftMouseDown monitor (C.6) so the first
        // click still reaches Ghostty — do not steal/eat here.
        guard let surface else { return }
        let mods = GhosttyInput.mods(event.modifierFlags)
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, mods)
        reportMousePos(event)
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface else { return }
        let mods = GhosttyInput.mods(event.modifierFlags)
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, mods)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let surface else {
            super.rightMouseDown(with: event)
            return
        }
        let mods = GhosttyInput.mods(event.modifierFlags)
        // Ghostty: if not consumed (e.g. context-menu action), let AppKit
        // call `menu(for:)` via super — otherwise the menu never appears.
        if ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, mods) {
            return
        }
        super.rightMouseDown(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface else {
            super.rightMouseUp(with: event)
            return
        }
        let mods = GhosttyInput.mods(event.modifierFlags)
        if ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, mods) {
            return
        }
        super.rightMouseUp(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let surface else { return }
        let mods = GhosttyInput.mods(event.modifierFlags)
        let button = GhosttyInput.mouseButton(event.buttonNumber)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, button, mods)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard let surface else { return }
        let mods = GhosttyInput.mods(event.modifierFlags)
        let button = GhosttyInput.mouseButton(event.buttonNumber)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, button, mods)
    }

    override func mouseMoved(with event: NSEvent) {
        reportMousePos(event)
    }

    override func mouseDragged(with event: NSEvent) {
        reportMousePos(event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        reportMousePos(event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        reportMousePos(event)
    }

    override func mouseEntered(with event: NSEvent) {
        // Reset cursor into the viewport after exit's -1/-1 (Ghostty: needed for
        // mouse-report / scrollback hit-testing after re-entry).
        reportMousePos(event)
    }

    override func mouseExited(with event: NSEvent) {
        guard let surface else { return }
        // Negative coords = left viewport (Ghostty convention).
        ghostty_surface_mouse_pos(surface, -1, -1, GhosttyInput.mods(event.modifierFlags))
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY
        let precision = event.hasPreciseScrollingDeltas
        if precision {
            x *= 2
            y *= 2
        }
        let scrollMods = GhosttyInput.scrollMods(
            precision: precision,
            momentum: event.momentumPhase
        )
        ghostty_surface_mouse_scroll(surface, x, y, scrollMods)
    }

    /// Focus this surface on left-click without consuming the event so Ghostty
    /// still gets the press (inactive-window first click + in-window focus).
    /// Diverges from Ghostty's split-focus eat path on purpose (C.6).
    private func handleLocalLeftMouseDown(_ event: NSEvent) -> NSEvent? {
        guard let window,
              event.window === window,
              let content = window.contentView else { return event }
        let location = content.convert(event.locationInWindow, from: nil)
        guard content.hitTest(location) === self else { return event }
        if window.firstResponder !== self {
            window.makeFirstResponder(self)
        }
        return event
    }

    private func installLocalEventMonitor() {
        guard localEventMonitor == nil else { return }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.handleLocalLeftMouseDown(event) ?? event
        }
    }

    private func removeLocalEventMonitor() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    private func reportMousePos(_ event: NSEvent) {
        guard let surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        // Ghostty surface coords: top-left origin.
        ghostty_surface_mouse_pos(
            surface,
            pos.x,
            bounds.height - pos.y,
            GhosttyInput.mods(event.modifierFlags)
        )
    }

    // MARK: - Clipboard / context menu (C.5)

    override func menu(for event: NSEvent) -> NSMenu? {
        switch event.type {
        case .rightMouseDown:
            break
        case .leftMouseDown:
            // Ctrl+left → context menu when mouse is not captured (Ghostty pattern).
            guard event.modifierFlags.contains(.control) else { return nil }
            guard let surface, !ghostty_surface_mouse_captured(surface) else { return nil }
            let mods = GhosttyInput.mods(event.modifierFlags)
            _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, mods)
        default:
            return nil
        }

        let menu = NSMenu()
        if let surface, ghostty_surface_has_selection(surface) {
            menu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
        }
        menu.addItem(withTitle: "Paste", action: #selector(paste(_:)), keyEquivalent: "")
        return menu
    }

    @objc func copy(_ sender: Any?) {
        guard let surface else { return }
        let action = "copy_to_clipboard"
        _ = ghostty_surface_binding_action(surface, action, UInt(action.utf8.count))
    }

    @objc func paste(_ sender: Any?) {
        guard let surface else { return }
        let action = "paste_from_clipboard"
        _ = ghostty_surface_binding_action(surface, action, UInt(action.utf8.count))
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copy(_:)):
            guard let surface else { return false }
            return ghostty_surface_has_selection(surface)
        case #selector(paste(_:)):
            return true
        default:
            return true
        }
    }

    private static func view(from userdata: UnsafeMutableRawPointer?) -> TerminalSurfaceNSView? {
        guard let userdata else { return nil }
        return Unmanaged<TerminalSurfaceNSView>.fromOpaque(userdata).takeUnretainedValue()
    }

    /// Ghostty → NSPasteboard (select-to-copy, ⌘C, OSC-52 write). Auto-confirm writes.
    private static func writeClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        content: UnsafePointer<ghostty_clipboard_content_s>?,
        len: Int,
        confirm: Bool
    ) {
        _ = confirm // C.5: no confirm sheet — always write.
        guard let pasteboard = NSPasteboard.ghostty(location) else { return }
        guard let content, len > 0 else { return }

        var items: [(mime: String, data: String)] = []
        items.reserveCapacity(len)
        for i in 0..<len {
            let entry = content[i]
            guard let mimePtr = entry.mime, let dataPtr = entry.data else { continue }
            items.append((String(cString: mimePtr), String(cString: dataPtr)))
        }
        guard !items.isEmpty else { return }

        let types = items.compactMap { NSPasteboard.PasteboardType(mimeType: $0.mime) }
        pasteboard.declareTypes(types, owner: nil)
        for item in items {
            guard let type = NSPasteboard.PasteboardType(mimeType: item.mime) else { continue }
            pasteboard.setString(item.data, forType: type)
        }

        // Select-to-copy / ⌘C / menu Copy — brief surface HUD.
        if let view = view(from: userdata) {
            DispatchQueue.main.async { view.showClipboardToast("Copied") }
        }
    }

    /// NSPasteboard → Ghostty paste / OSC-52 read. Returns false when empty so
    /// performable paste bindings can pass through to the terminal.
    private static func readClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        state: UnsafeMutableRawPointer?
    ) -> Bool {
        guard let view = view(from: userdata), let surface = view.surface else { return false }
        guard let pasteboard = NSPasteboard.ghostty(location) else { return false }
        guard let str = pasteboard.getOpinionatedStringContents() else { return false }
        completeClipboardRequest(surface, data: str, state: state, confirmed: false)
        // Confirm (if any) runs sync inside complete; toast once after it returns.
        DispatchQueue.main.async { view.showClipboardToast("Pasted") }
        return true
    }

    /// C.5: auto-confirm paste / OSC-52 read (no sheet).
    private static func confirmReadClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        string: UnsafePointer<CChar>?,
        state: UnsafeMutableRawPointer?,
        request: ghostty_clipboard_request_e
    ) {
        _ = request
        guard let view = view(from: userdata), let surface = view.surface else { return }
        let str = string.map { String(cString: $0) } ?? ""
        completeClipboardRequest(surface, data: str, state: state, confirmed: true)
    }

    private static func completeClipboardRequest(
        _ surface: ghostty_surface_t,
        data: String,
        state: UnsafeMutableRawPointer?,
        confirmed: Bool
    ) {
        data.withCString { ptr in
            ghostty_surface_complete_clipboard_request(surface, ptr, state, confirmed)
        }
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
            let count = spawnEnvironment.count
            let buffer = UnsafeMutablePointer<ghostty_env_var_s>.allocate(capacity: count)
            envVarsBuffer = buffer
            for (index, pair) in spawnEnvironment.enumerated() {
                let keyPtr = strdup(pair.key)!
                let valuePtr = strdup(pair.value)!
                envKeyCStrings.append(keyPtr)
                envValueCStrings.append(valuePtr)
                buffer[index] = ghostty_env_var_s(key: keyPtr, value: valuePtr)
            }
            surfaceConfig.env_vars = buffer
            surfaceConfig.env_var_count = count
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

    private func tearDownGhostty() {
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

    private func syncSurfaceGeometry() {
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
    private func syncLayerContentsScale(for window: NSWindow) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contentsScale = window.backingScaleFactor
        CATransaction.commit()
    }

    private func syncDisplayID(for window: NSWindow) {
        guard let surface, let screen = window.screen else { return }
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) ?? 0
        ghostty_surface_set_display_id(surface, displayID)
    }

    private func installScreenObserver() {
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

    private func removeScreenObserver() {
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
            self.screenChangeObserver = nil
        }
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

    /// Small auto-dismiss HUD for clipboard success (surface-local, not Status Cue).
    private func showClipboardToast(_ message: String) {
        clipboardToastHideWorkItem?.cancel()
        clipboardToastHideWorkItem = nil

        let label: NSTextField
        if let clipboardToastLabel {
            label = clipboardToastLabel
            label.stringValue = "  \(message)  "
        } else {
            label = NSTextField(labelWithString: "  \(message)  ")
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .white
            label.alignment = .center
            label.drawsBackground = false
            label.wantsLayer = true
            label.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
            label.layer?.cornerRadius = 6
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
                label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            ])
            label.setContentHuggingPriority(.required, for: .horizontal)
            clipboardToastLabel = label
        }

        label.alphaValue = 1

        let work = DispatchWorkItem { [weak self] in
            guard let self, let toast = self.clipboardToastLabel else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                toast.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                self?.clipboardToastLabel?.removeFromSuperview()
                self?.clipboardToastLabel = nil
                self?.clipboardToastHideWorkItem = nil
            })
        }
        clipboardToastHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }
}

// MARK: - Input helpers (from Ghostty NSEvent+Extension / Ghostty.Input)

private enum GhosttyInput {
    static func mods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var mods: UInt32 = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }
        return ghostty_input_mods_e(mods)
    }

    static func eventModifierFlags(mods: ghostty_input_mods_e) -> NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags(rawValue: 0)
        if mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0 { flags.insert(.shift) }
        if mods.rawValue & GHOSTTY_MODS_CTRL.rawValue != 0 { flags.insert(.control) }
        if mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0 { flags.insert(.option) }
        if mods.rawValue & GHOSTTY_MODS_SUPER.rawValue != 0 { flags.insert(.command) }
        return flags
    }

    static func mouseButton(_ buttonNumber: Int) -> ghostty_input_mouse_button_e {
        switch buttonNumber {
        case 0: return GHOSTTY_MOUSE_LEFT
        case 1: return GHOSTTY_MOUSE_RIGHT
        case 2: return GHOSTTY_MOUSE_MIDDLE
        case 3: return GHOSTTY_MOUSE_FOUR
        case 4: return GHOSTTY_MOUSE_FIVE
        default: return GHOSTTY_MOUSE_UNKNOWN
        }
    }

    static func scrollMods(precision: Bool, momentum: NSEvent.Phase) -> ghostty_input_scroll_mods_t {
        var value: Int32 = 0
        if precision { value |= 0b1 }
        let momentumBits: UInt8
        switch momentum {
        case .began: momentumBits = 1
        case .stationary: momentumBits = 2
        case .changed: momentumBits = 3
        case .ended: momentumBits = 4
        case .cancelled: momentumBits = 5
        case .mayBegin: momentumBits = 6
        default: momentumBits = 0
        }
        value |= Int32(momentumBits) << 1
        return value
    }
}

private extension NSEvent {
    func ghosttyKeyEvent(
        _ action: ghostty_input_action_e,
        translationMods: NSEvent.ModifierFlags? = nil
    ) -> ghostty_input_key_s {
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = action
        keyEvent.keycode = UInt32(keyCode)
        keyEvent.text = nil
        keyEvent.composing = false
        keyEvent.mods = GhosttyInput.mods(modifierFlags)
        keyEvent.consumed_mods = GhosttyInput.mods(
            (translationMods ?? modifierFlags).subtracting([.control, .command])
        )
        keyEvent.unshifted_codepoint = 0
        if type == .keyDown || type == .keyUp {
            if let chars = characters(byApplyingModifiers: []),
               let codepoint = chars.unicodeScalars.first {
                keyEvent.unshifted_codepoint = codepoint.value
            }
        }
        return keyEvent
    }

    var ghosttyCharacters: String? {
        guard let characters else { return nil }
        if characters.count == 1, let scalar = characters.unicodeScalars.first {
            if scalar.value < 0x20 {
                return self.characters(byApplyingModifiers: modifierFlags.subtracting(.control))
            }
            // Function-key PUA — Ghostty encodes from keycode.
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return nil
            }
        }
        return characters
    }
}

// MARK: - Pasteboard helpers (Ghostty NSPasteboard+Extension, slimmed for C.5)

private extension NSPasteboard.PasteboardType {
    init?(mimeType: String) {
        switch mimeType {
        case "text/plain":
            self = .string
        default:
            self.init(mimeType)
        }
    }
}

private extension NSPasteboard {
    /// Ghostty selection pasteboard (copy-on-select default destination on macOS).
    static var ghosttySelection: NSPasteboard = {
        NSPasteboard(name: .init("com.mitchellh.ghostty.selection"))
    }()

    static func ghostty(_ clipboard: ghostty_clipboard_e) -> NSPasteboard? {
        switch clipboard {
        case GHOSTTY_CLIPBOARD_STANDARD:
            return .general
        case GHOSTTY_CLIPBOARD_SELECTION:
            return .ghosttySelection
        default:
            return nil
        }
    }

    /// Prefer file-URL paths (shell-escaped) then plain strings — Ghostty paste semantics.
    func getOpinionatedStringContents() -> String? {
        let strings = (pasteboardItems ?? []).compactMap { item -> String? in
            if let plist = item.propertyList(forType: .fileURL),
               let fileURL = NSURL(pasteboardPropertyList: plist, ofType: .fileURL) as URL?,
               fileURL.isFileURL {
                return TerminalShell.escape(fileURL.path)
            }
            return item.string(forType: .string)
        }
        guard !strings.isEmpty else { return nil }
        return strings.joined(separator: " ")
    }
}

private enum TerminalShell {
    private static let escapeCharacters = "\\ ()[]{}<>\"'`!#$&;|*?\t"

    static func escape(_ str: String) -> String {
        var result = str
        for char in escapeCharacters {
            result = result.replacingOccurrences(of: String(char), with: "\\\(char)")
        }
        return result
    }
}

/// SwiftUI bridge for the AppKit terminal island (ADR 0011).
///
/// Intentionally not `.focusable()` — AppKit first-responder owns typing focus
/// so SwiftUI does not steal key events from the surface.
///
/// When `workingDirectory` / `command` / `spawnEnvironment` change, the surface restarts.
/// Nil command = bare shell. `isActive` only toggles focus — it does not respawn.
struct TerminalSurfaceView: NSViewRepresentable {
    var workingDirectory: String? = nil
    var command: String? = nil
    /// Locale defaults + Enabled Secret Store pairs at spawn.
    var spawnEnvironment: [(key: String, value: String)] = []
    /// Visible / keyboard-owning surface (Main CLI or peeked Overlay).
    var isActive: Bool = true

    func makeNSView(context: Context) -> TerminalSurfaceNSView {
        let view = TerminalSurfaceNSView(frame: .zero)
        view.applySpawnConfig(
            workingDirectory: workingDirectory,
            command: command,
            spawnEnvironment: spawnEnvironment
        )
        return view
    }

    func updateNSView(_ nsView: TerminalSurfaceNSView, context: Context) {
        nsView.applySpawnConfig(
            workingDirectory: workingDirectory,
            command: command,
            spawnEnvironment: spawnEnvironment
        )
        nsView.setActive(isActive)
    }
}

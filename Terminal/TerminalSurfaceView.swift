import AppKit
import GhosttyKit
import SwiftUI

/// Owns one Ghostty app + surface bound to this `NSView` (ADR 2026-07-23-0011-swiftui-chrome-appkit-terminal).
///
/// P1.1: render surface. P1.3: AppKit first-responder + key/mouse → `ghostty_surface_*`
/// (mirrors Ghostty's `SurfaceView_AppKit` / `NSEvent+Extension` patterns).
/// C.5: Ghostty ↔ NSPasteboard (select-to-copy, ⌘C/⌘V, right-click Copy/Paste).
/// C.6: scrollback enter reset, font zoom via bindings, click-to-focus without eating.
/// Symphonia-owned PTY / session lifecycle remains P1.2.
final class TerminalSurfaceNSView: NSView, NSMenuItemValidation {
    var ghosttyApp: ghostty_app_t?
    var ghosttyConfig: ghostty_config_t?
    var surface: ghostty_surface_t?
    var statusLabel: NSTextField?
    /// Ephemeral “Copied” / “Pasted” HUD (auto-dismiss).
    var clipboardToastLabel: NSTextField?
    var clipboardToastHideWorkItem: DispatchWorkItem?
    /// Local monitor: focus on left-click without eating the event (C.6).
    var localEventMonitor: Any?
    var didStart = false
    var surfaceFocused = false

    /// Spawn config for Ghostty surface (P4.5 / P5.3). Empty command = bare shell / Ghostty default.
    var workingDirectory: String?
    var command: String?
    /// Enabled Secret Store Env Vars for this spawn (empty = no Secret Store inject).
    var spawnEnvironment: [(key: String, value: String)] = []

    /// Retained C strings for `ghostty_surface_config_s` (must outlive `ghostty_surface_new`).
    var workingDirectoryCString: UnsafeMutablePointer<CChar>?
    var commandCString: UnsafeMutablePointer<CChar>?
    var envKeyCStrings: [UnsafeMutablePointer<CChar>] = []
    var envValueCStrings: [UnsafeMutablePointer<CChar>] = []
    var envVarsBuffer: UnsafeMutablePointer<ghostty_env_var_s>?

    /// Accumulates `insertText` while handling `keyDown` via `interpretKeyEvents`
    /// (same pattern as Ghostty's SurfaceView).
    var keyTextAccumulator: [String]?

    /// Observes window screen changes (Retina ↔ external) so we re-sync scale/size.
    var screenChangeObserver: NSObjectProtocol?

    /// Fired on the main queue when Ghostty reports the surface process exited (`exit`, `:q`, …).
    var onProcessExit: (() -> Void)?
    /// Fired when Ghostty reports the child command exited (wait-after-command / SHOW_CHILD_EXITED).
    var onChildExited: ((UInt32) -> Void)?
    /// When set, accept first-responder and invoke on any key (does not write to the PTY).
    var onContinueKey: (() -> Void)?
    /// When true, swallow keyboard input and decline first-responder (scroll/select still work).
    /// Ignored for first-responder when `onContinueKey` is set.
    var isReadOnly = false

    override var acceptsFirstResponder: Bool { !isReadOnly || onContinueKey != nil }

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
            guard !self.isReadOnly || self.onContinueKey != nil else { return }
            window.makeFirstResponder(self)
        }
    }

    /// Toggle host-side read-only (does not respawn).
    func setReadOnly(_ readOnly: Bool) {
        isReadOnly = readOnly
        if readOnly, onContinueKey == nil, window?.firstResponder === self {
            window?.makeFirstResponder(nil)
            setSurfaceFocus(false)
        }
    }

    /// Arm/disarm “press any key to continue” without writing to the PTY.
    func setContinueKey(_ handler: (() -> Void)?) {
        onContinueKey = handler
        guard window != nil else { return }
        if handler != nil {
            window?.makeFirstResponder(self)
            setSurfaceFocus(false)
        } else if isReadOnly, window?.firstResponder === self {
            window?.makeFirstResponder(nil)
            setSurfaceFocus(false)
        }
    }

    /// When this surface becomes the visible Main CLI / Overlay, take keyboard focus.
    func setActive(_ active: Bool) {
        guard window != nil else { return }
        if active {
            if window?.firstResponder !== self {
                window?.makeFirstResponder(self)
            }
            // Continue-key capture owns AppKit focus without Ghostty PTY focus.
            setSurfaceFocus(onContinueKey == nil)
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
            guard !self.isReadOnly || self.onContinueKey != nil else { return }
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

    func setSurfaceFocus(_ focused: Bool) {
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
        if let onContinueKey {
            onContinueKey()
            return
        }
        guard !isReadOnly else { return }
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
        if onContinueKey != nil { return }
        guard !isReadOnly else { return }
        _ = sendKey(GHOSTTY_ACTION_RELEASE, event: event)
    }

    override func flagsChanged(with event: NSEvent) {
        if onContinueKey != nil { return }
        guard !isReadOnly else { return }
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
        if onContinueKey != nil { return }
        guard !isReadOnly else { return }
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
    ///
    /// Menu / window shortcuts (⌘W close, ⌘Q quit, ⌘,, …) always defer to AppKit so
    /// Ghostty surface bindings cannot swallow Symphonia chrome shortcuts.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }

        // App menu wins over libghostty bindings (Close Window, Settings, Quit, …).
        if Self.mainMenuHasKeyEquivalent(event) {
            return false
        }
        if onContinueKey != nil {
            return false // deliver as keyDown → continue
        }
        guard !isReadOnly else { return false }

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

    /// True when `NSApp.mainMenu` has an enabled item for this key equivalent.
    private static func mainMenuHasKeyEquivalent(_ event: NSEvent) -> Bool {
        guard let menu = NSApp.mainMenu else { return false }
        return menuItemMatchingKeyEquivalent(event, in: menu) != nil
    }

    private static func menuItemMatchingKeyEquivalent(_ event: NSEvent, in menu: NSMenu) -> NSMenuItem? {
        let eventMods = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .option, .control, .shift])
        let chars = event.charactersIgnoringModifiers ?? ""
        guard !chars.isEmpty else { return nil }

        for item in menu.items {
            if let submenu = item.submenu,
               let found = menuItemMatchingKeyEquivalent(event, in: submenu)
            {
                return found
            }
            let equiv = item.keyEquivalent
            guard !equiv.isEmpty else { continue }
            let itemMods = item.keyEquivalentModifierMask
                .intersection(.deviceIndependentFlagsMask)
                .intersection([.command, .option, .control, .shift])
            guard itemMods == eventMods else { continue }
            // Menu keyEquivalents are typically lowercase; compare case-insensitively.
            if equiv.compare(chars, options: [.caseInsensitive, .literal]) == .orderedSame {
                return item
            }
        }
        return nil
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

}

/// SwiftUI bridge for the AppKit terminal island (ADR 2026-07-23-0011-swiftui-chrome-appkit-terminal).
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
    /// Swallow keyboard → PTY (scroll/select still work). Used for create-progress.
    var isReadOnly: Bool = false
    /// Domain policy for PTY exit (Main auto-reload, Overlay close, …).
    var onProcessExit: (() -> Void)? = nil
    /// Fired when the surface child command exits (includes exit code).
    var onChildExited: ((UInt32) -> Void)? = nil
    /// When set, any key continues (host-side; no PTY write). Used after create-progress succeeds.
    var onContinueKey: (() -> Void)? = nil

    func makeNSView(context: Context) -> TerminalSurfaceNSView {
        let view = TerminalSurfaceNSView(frame: .zero)
        view.onProcessExit = onProcessExit
        view.onChildExited = onChildExited
        view.onContinueKey = onContinueKey
        view.isReadOnly = isReadOnly
        view.applySpawnConfig(
            workingDirectory: workingDirectory,
            command: command,
            spawnEnvironment: spawnEnvironment
        )
        return view
    }

    func updateNSView(_ nsView: TerminalSurfaceNSView, context: Context) {
        nsView.onProcessExit = onProcessExit
        nsView.onChildExited = onChildExited
        nsView.setContinueKey(onContinueKey)
        nsView.setReadOnly(isReadOnly)
        nsView.applySpawnConfig(
            workingDirectory: workingDirectory,
            command: command,
            spawnEnvironment: spawnEnvironment
        )
        let wantsKeys = isActive || onContinueKey != nil
        nsView.setActive(wantsKeys && (!isReadOnly || onContinueKey != nil))
    }
}

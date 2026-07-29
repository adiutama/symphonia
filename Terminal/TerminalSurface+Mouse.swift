import AppKit
import GhosttyKit

extension TerminalSurfaceNSView {
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

    func installLocalEventMonitor() {
        guard localEventMonitor == nil else { return }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.handleLocalLeftMouseDown(event) ?? event
        }
    }

    func removeLocalEventMonitor() {
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
}

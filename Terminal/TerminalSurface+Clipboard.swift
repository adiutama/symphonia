import AppKit
import GhosttyKit

extension TerminalSurfaceNSView {
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
    static func writeClipboard(
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
    static func readClipboard(
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
    static func confirmReadClipboard(
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

    /// Small auto-dismiss HUD for clipboard success (surface-local).
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

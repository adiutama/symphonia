import AppKit
import GhosttyKit

/// Pasteboard helpers from Ghostty `NSPasteboard+Extension` (slimmed for C.5).
extension NSPasteboard.PasteboardType {
    init?(mimeType: String) {
        switch mimeType {
        case "text/plain":
            self = .string
        default:
            self.init(mimeType)
        }
    }
}

extension NSPasteboard {
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

enum TerminalShell {
    private static let escapeCharacters = "\\ ()[]{}<>\"'`!#$&;|*?\t"

    static func escape(_ str: String) -> String {
        var result = str
        for char in escapeCharacters {
            result = result.replacingOccurrences(of: String(char), with: "\\\(char)")
        }
        return result
    }
}

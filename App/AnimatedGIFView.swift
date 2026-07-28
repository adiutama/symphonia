import AppKit
import SwiftUI

/// Plays a bundled animated GIF via `NSImageView` (SwiftUI `Image` only shows frame 0).
struct AnimatedGIFView: NSViewRepresentable {
    /// Resource basename inside `OnboardingMedia/` (no extension).
    let resourceName: String

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.imageAlignment = .alignCenter
        view.animates = true
        view.canDrawSubviewsIntoLayer = true
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        view.image = Self.loadGIF(named: resourceName)
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        let image = Self.loadGIF(named: resourceName)
        if nsView.image !== image {
            nsView.image = image
        }
        nsView.animates = true
    }

    static func loadGIF(named name: String) -> NSImage? {
        if let url = Bundle.main.url(
            forResource: name,
            withExtension: "gif",
            subdirectory: "OnboardingMedia"
        ) {
            return NSImage(contentsOf: url)
        }
        // Flat copy fallback (if the folder was flattened into Resources).
        if let url = Bundle.main.url(forResource: name, withExtension: "gif") {
            return NSImage(contentsOf: url)
        }
        return nil
    }

    static func hasGIF(named name: String) -> Bool {
        loadGIF(named: name) != nil
    }
}

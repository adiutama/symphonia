# SwiftUI chrome + AppKit terminal surface

v1 uses **SwiftUI** for app chrome (Command Center, Secret Store, Overlay Switcher, settings) and an **AppKit-backed** view (via representable) for each libghostty terminal surface (Main CLI, Editor Overlay, Background CLIs).

Symphonia’s product is management UX; SwiftUI fits that and maps better for a web-background Operator. Terminal fidelity still needs an imperative AppKit/Metal island — that is expected, not a failure of SwiftUI.

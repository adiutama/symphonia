import Foundation

/// Sparkle update channel — Stable (tagged releases) vs Nightly (pre-release builds).
enum UpdateChannel: String, Codable, CaseIterable, Identifiable, Sendable {
    case stable
    case nightly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stable: return "Stable"
        case .nightly: return "Nightly"
        }
    }

    /// Sparkle appcast for this channel (GitHub Releases assets).
    var feedURL: URL {
        switch self {
        case .stable:
            return URL(string: "https://github.com/adiutama/symphonia/releases/latest/download/appcast.xml")!
        case .nightly:
            return URL(string: "https://github.com/adiutama/symphonia/releases/download/nightly/appcast.xml")!
        }
    }
}

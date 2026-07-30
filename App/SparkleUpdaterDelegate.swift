import Foundation
import Sparkle

/// Supplies the Sparkle feed URL from the Operator’s selected ``UpdateChannel``.
final class SparkleUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    /// Called on each update check; keep this cheap and current.
    var channelProvider: () -> UpdateChannel = { .stable }

    func feedURLString(for updater: SPUUpdater) -> String? {
        channelProvider().feedURL.absoluteString
    }
}

/// Thin hold on Sparkle so Settings / menus can check for updates and reset the cycle.
@MainActor
final class SparkleUpdateController: ObservableObject {
    let updaterController: SPUStandardUpdaterController
    let delegate: SparkleUpdaterDelegate

    var updater: SPUUpdater { updaterController.updater }

    init(delegate: SparkleUpdaterDelegate, updaterController: SPUStandardUpdaterController) {
        self.delegate = delegate
        self.updaterController = updaterController
    }

    /// After switching channels, reset Sparkle’s schedule so the new feed is used promptly.
    func noteChannelChanged() {
        updater.resetUpdateCycle()
    }
}

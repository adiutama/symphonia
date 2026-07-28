import AppKit
import SwiftUI

/// Compact directory path field + Browse… (Settings Workspaces Root / Prefix).
struct DirectoryPathField: View {
    @Binding var path: String
    var prompt: String = "Path"

    var body: some View {
        HStack(spacing: 8) {
            TextField(prompt, text: $path, prompt: Text(prompt))
                .settingsControlField()
                .frame(minWidth: 140, idealWidth: 200)
                .frame(maxWidth: 280)

            Button("Browse…") {
                browse()
            }
        }
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose a directory"

        let expanded = SymphoniaPaths.expandingTildeInPath(path)
        if !path.isEmpty, FileManager.default.fileExists(atPath: expanded.path) {
            panel.directoryURL = expanded
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        path = Self.displayPath(for: url)
    }

    /// Prefer `~/…` when under the Operator home directory.
    static func displayPath(for url: URL) -> String {
        let standardized = url.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if standardized == home {
            return "~"
        }
        if standardized.hasPrefix(home + "/") {
            return "~" + standardized.dropFirst(home.count)
        }
        return standardized
    }
}

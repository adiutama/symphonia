import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Kind pickers

/// Kind-first Presentation picker — short labels; copy explains Overlay vs External (ADR 0023).
struct PresentationKindPicker: View {
    @Binding var presentation: EditorPresentation

    var body: some View {
        Picker("", selection: $presentation) {
            Text("TUI").tag(EditorPresentation.terminalOverlay)
            Text("GUI").tag(EditorPresentation.externalApp)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 120)
        .help("TUI opens as Overlay (peek/hide). GUI opens as External (Focus / End).")
    }
}

/// Optional Presentation picker with inherit sentinel for Workspace overrides.
struct OptionalPresentationKindPicker: View {
    @Binding var presentation: EditorPresentation?

    var body: some View {
        Picker("", selection: $presentation) {
            Text("Inherit").tag(Optional<EditorPresentation>.none)
            Text("TUI").tag(Optional(EditorPresentation.terminalOverlay))
            Text("GUI").tag(Optional(EditorPresentation.externalApp))
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 200)
        .help("TUI = Overlay; GUI = External; Inherit uses Global.")
    }
}

// MARK: - App field

/// App identity: icon, monospaced bundle id, folder picker, resolved display name.
struct BundleIDField: View {
    @Binding var bundleID: String
    var placeholder: String

    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme

    private var resolvedBundleID: String {
        BundleIDResolver.resolve(bundleID.isEmpty ? placeholder : bundleID)
    }

    private var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: resolvedBundleID)
    }

    private var displayName: String? {
        guard let appURL else { return nil }
        return FileManager.default.displayName(atPath: appURL.path)
    }

    private var appIcon: NSImage? {
        guard let appURL else { return nil }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if let appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 28, height: 28)
                        .cornerRadius(6)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(ghosttyTheme.control)
                        .frame(width: 28, height: 28)
                        .overlay {
                            Image(systemName: "app.dashed")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(ghosttyTheme.tertiaryText)
                        }
                }

                TextField(placeholder, text: $bundleID)
                    .font(.system(size: 12, design: .monospaced))
                    .settingsControlField()
                    .frame(maxWidth: .infinity)

                Button {
                    pickApplication()
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ghosttyTheme.secondaryText)
                        .frame(width: 32, height: 32)
                        .background(ghosttyTheme.control)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Choose App…")
                .accessibilityLabel("Choose App")
            }

            if let displayName {
                Text(displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ghosttyTheme.secondaryText)
            }
        }
    }

    private func pickApplication() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.message = "Choose a macOS application"
        if let appURL {
            panel.directoryURL = appURL.deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let id = Bundle(url: url)?.bundleIdentifier, !id.isEmpty {
            bundleID = id
        } else {
            bundleID = url.path
        }
    }
}

// MARK: - Activity section chrome

/// Spacious Activity tool card — header, Presentation, then a full-width value field.
struct ActivitySettingsSection<Content: View>: View {
    let title: String
    let systemImage: String
    let blurb: String
    var badge: String?
    @ViewBuilder var content: () -> Content

    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ghosttyTheme.foreground.opacity(0.9))
                    .frame(width: 36, height: 36)
                    .background(ghosttyTheme.control)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(ghosttyTheme.foreground)
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(ghosttyTheme.secondaryText)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(ghosttyTheme.control)
                                .clipShape(Capsule())
                        }
                    }
                    Text(blurb)
                        .font(.caption)
                        .foregroundStyle(ghosttyTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ghosttyTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ActivityFieldLabel: View {
    let title: String
    var detail: String?

    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ghosttyTheme.foreground)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(ghosttyTheme.tertiaryText)
            }
        }
    }
}

/// Global Editor / Files — Presentation row, then full-width command or app.
struct ActivityPresentationConfigurator: View {
    @Binding var presentation: EditorPresentation
    @Binding var command: String
    @Binding var bundleID: String
    var commandPlaceholder: String
    var commandDetail: String
    var bundlePlaceholder: String
    var bundleDetail: String

    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ActivityFieldLabel(
                    title: "Presentation",
                    detail: presentation == .terminalOverlay
                        ? "Overlay — peek and hide without quitting"
                        : "External — Focus / End only (no peek)"
                )
                Spacer(minLength: 12)
                PresentationKindPicker(presentation: $presentation)
            }

            SoftHairline()

            if presentation == .terminalOverlay {
                VStack(alignment: .leading, spacing: 8) {
                    ActivityFieldLabel(title: "Command", detail: commandDetail)
                    TextField(commandPlaceholder, text: $command)
                        .settingsControlField()
                        .frame(maxWidth: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ActivityFieldLabel(title: "Application", detail: bundleDetail)
                    BundleIDField(bundleID: $bundleID, placeholder: bundlePlaceholder)
                }
            }
        }
    }
}

/// Workspace Editor / Files — Inherit / TUI / GUI, then value fields.
struct OptionalActivityPresentationConfigurator: View {
    @Binding var presentation: EditorPresentation?
    @Binding var command: String?
    @Binding var bundleID: String?
    var resolvedPresentation: EditorPresentation
    var commandPlaceholder: String
    var commandDetail: String
    var bundlePlaceholder: String
    var bundleDetail: String

    private var effectivePresentation: EditorPresentation {
        presentation ?? resolvedPresentation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ActivityFieldLabel(
                    title: "Presentation",
                    detail: presentation == nil
                        ? "Inherits Global (\(effectivePresentation == .terminalOverlay ? "TUI" : "GUI"))"
                        : (effectivePresentation == .terminalOverlay
                            ? "Overlay — peek and hide without quitting"
                            : "External — Focus / End only")
                )
                Spacer(minLength: 12)
                OptionalPresentationKindPicker(presentation: $presentation)
            }

            SoftHairline()

            if effectivePresentation == .terminalOverlay {
                VStack(alignment: .leading, spacing: 8) {
                    ActivityFieldLabel(title: "Command", detail: commandDetail)
                    TextField(
                        commandPlaceholder,
                        text: Binding(
                            get: { command ?? "" },
                            set: { command = $0.isEmpty ? nil : $0 }
                        )
                    )
                    .settingsControlField()
                    .frame(maxWidth: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ActivityFieldLabel(title: "Application", detail: bundleDetail)
                    BundleIDField(
                        bundleID: Binding(
                            get: { bundleID ?? "" },
                            set: { bundleID = $0.isEmpty ? nil : $0 }
                        ),
                        placeholder: bundlePlaceholder
                    )
                }
            }
        }
    }
}

/// Shell Activity — Overlay-only; optional default command.
struct ShellActivityConfigurator: View {
    @Binding var command: String
    var detail: String = "Empty opens a login shell in the Worktree."

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ActivityFieldLabel(title: "Default command", detail: detail)
            TextField("Empty = login shell", text: $command)
                .settingsControlField()
                .frame(maxWidth: .infinity)
        }
    }
}

import AppKit
import SwiftUI

/// Glance — Activity Manager UI (ADR 0023).
///
/// Compact inventory of Activities for the focused Worktree: Changes, Shells, Editors, Files.
/// Overlay Activities support Focus (peek) / Hide; External Activities support Focus / End only.
struct GlanceHUD: View {
    @EnvironmentObject private var overlays: OverlayController
    @EnvironmentObject private var activities: ActivityManager
    @EnvironmentObject private var worktrees: WorktreeController
    @EnvironmentObject private var preferences: PreferencesController
    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme

    @StateObject private var diffMonitor = GitDiffStatsMonitor()
    @State private var renameTarget: GlanceRenameTarget?
    @State private var renameDraft = ""

    private let cardWidth: CGFloat = 240
    private let cornerRadius: CGFloat = 16

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var focusedSessionId: String? {
        worktrees.focusedSession?.id
    }

    private var focusedWorkingDirectory: URL? {
        worktrees.focusedSession.map { URL(fileURLWithPath: $0.workingDirectory) }
    }

    /// Shell Activities with Overlay Presentation (Background CLIs).
    private var shells: [OverlaySession] {
        overlays.focusedSessions.filter { $0.kind == .background }
    }

    /// Editor Activities with Overlay Presentation.
    private var overlayEditors: [OverlaySession] {
        overlays.focusedSessions.filter { $0.kind == .editor }
    }

    /// External Editor Activities for the focused session.
    private var externalEditors: [ExternalActivity] {
        guard let sessionId = focusedSessionId else { return [] }
        return activities.externalActivities(for: sessionId, kind: .editor)
    }

    /// Files Activities — Overlay TUI and External GUI.
    private var overlayFiles: [OverlaySession] {
        overlays.focusedSessions.filter { $0.kind == .files }
    }

    private var externalFiles: [ExternalActivity] {
        guard let sessionId = focusedSessionId else { return [] }
        return activities.externalActivities(for: sessionId, kind: .files)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            changesSection
            sectionDivider
            categorySection(
                title: "Shells",
                systemImage: "terminal",
                overlaySessions: shells,
                externalActivities: [],
                emptyLabel: "None",
                addAction: {
                    overlays.draftBackgroundCommand = ""
                    overlays.createBackgroundCLI()
                },
                addHelp: "Open Shell"
            )
            sectionDivider
            categorySection(
                title: "Editors",
                systemImage: "pencil",
                overlaySessions: overlayEditors,
                externalActivities: externalEditors,
                emptyLabel: "None",
                addAction: {
                    activities.openEditor()
                },
                addHelp: "Open Editor"
            )
            sectionDivider
            filesSection
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: cardWidth, alignment: .topLeading)
        .background { cardVeil }
        .clipShape(cardShape)
        .shadow(color: .black.opacity(0.38), radius: 22, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Glance, Activity Manager")
        .onAppear {
            startDiffMonitoring()
            activities.refreshExternalInventory()
        }
        .onDisappear {
            diffMonitor.stop()
        }
        .onChange(of: worktrees.focusedSession?.id) { _, _ in
            startDiffMonitoring()
            activities.refreshExternalInventory()
        }
        .alert(
            "Rename",
            isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )
        ) {
            TextField("Name", text: $renameDraft)
            Button("Cancel", role: .cancel) {
                renameTarget = nil
            }
            Button("Rename") {
                applyRename()
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            Text("Local label in Glance only — does not rename the app or process.")
        }
    }

    // MARK: - Changes

    private var changesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Changes")

            HStack(spacing: 8) {
                Text("+\(diffMonitor.stats.inserted)")
                    .foregroundStyle(Color(red: 0.45, green: 0.78, blue: 0.52))
                Text("−\(diffMonitor.stats.deleted)")
                    .foregroundStyle(Color(red: 0.92, green: 0.45, blue: 0.45))
                Spacer(minLength: 0)
            }
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .padding(.vertical, 1)
            .animation(.easeInOut(duration: 0.15), value: diffMonitor.stats)
        }
        .padding(.bottom, 12)
    }

    private func startDiffMonitoring() {
        guard let directory = focusedWorkingDirectory else {
            diffMonitor.stop()
            return
        }
        diffMonitor.start(directory: directory)
    }

    // MARK: - Category (Shells / Editors)

    private func categorySection(
        title: String,
        systemImage: String,
        overlaySessions: [OverlaySession],
        externalActivities: [ExternalActivity],
        emptyLabel: String,
        addAction: (() -> Void)?,
        addHelp: String
    ) -> some View {
        let isEmpty = overlaySessions.isEmpty && externalActivities.isEmpty
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                sectionLabel(title)
                Spacer(minLength: 0)
                if let addAction {
                    Button(action: addAction) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ghosttyTheme.secondaryText)
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(addHelp)
                    .accessibilityLabel(addHelp)
                }
            }

            if isEmpty {
                Text(emptyLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(ghosttyTheme.tertiaryText)
                    .padding(.vertical, 3)
            } else {
                ForEach(overlaySessions) { session in
                    overlaySessionRow(session, systemImage: systemImage)
                }
                ForEach(externalActivities) { activity in
                    externalActivityRow(activity, systemImage: systemImage)
                }
            }
        }
        .padding(.vertical, 12)
    }

    private func overlaySessionRow(_ session: OverlaySession, systemImage: String) -> some View {
        let isFocused = overlays.visibleOverlayID == session.id
        let title = displayTitle(for: session)
        return HStack(spacing: 2) {
            Button {
                if isFocused {
                    overlays.hide()
                } else {
                    activities.focusOverlay(session.id)
                }
            } label: {
                activityRowLabel(
                    systemImage: systemImage,
                    title: title,
                    isFocused: isFocused,
                    trailing: nil
                )
            }
            .buttonStyle(.plain)
            .help(isFocused ? "Hide (keeps running)" : "Focus")

            activityActionsMenu(
                renameTitle: title,
                closeHelp: "End Overlay — kills the PTY",
                onRename: {
                    beginRename(.overlay(session.id), current: title)
                },
                onClose: {
                    activities.endOverlay(session.id)
                }
            )
        }
    }

    private func externalActivityRow(_ activity: ExternalActivity, systemImage: String) -> some View {
        let isFocused = activities.isExternalFocused(activity)
        let isFinder = activity.bundleID == ActivityDefaults.fileManagerBundleID
        return HStack(spacing: 2) {
            Button {
                activities.focusExternal(activity.id)
            } label: {
                activityRowLabel(
                    systemImage: systemImage,
                    title: activity.label,
                    isFocused: isFocused,
                    trailing: "external"
                )
            }
            .buttonStyle(.plain)
            .help("Focus")

            activityActionsMenu(
                renameTitle: activity.label,
                closeHelp: isFinder
                    ? "Close Finder windows for this Worktree (does not quit Finder)"
                    : "Quit the app and remove from Glance",
                onRename: {
                    beginRename(.external(activity.id), current: activity.label)
                },
                onClose: {
                    activities.endExternal(activity.id)
                }
            )
        }
    }

    private func activityActionsMenu(
        renameTitle: String,
        closeHelp: String,
        onRename: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) -> some View {
        Menu {
            Button("Rename…") {
                onRename()
            }
            Divider()
            Button("Close", role: .destructive) {
                onClose()
            }
            .help(closeHelp)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ghosttyTheme.tertiaryText)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Actions")
        .accessibilityLabel("Actions for \(renameTitle)")
    }

    private func activityRowLabel(
        systemImage: String,
        title: String,
        isFocused: Bool,
        trailing: String?
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(
                    isFocused
                        ? ghosttyTheme.foreground.opacity(0.9)
                        : ghosttyTheme.secondaryText
                )
                .frame(width: 14, alignment: .center)

            Text(title)
                .font(.system(size: 12, weight: isFocused ? .medium : .regular))
                .foregroundStyle(
                    isFocused
                        ? ghosttyTheme.foreground
                        : ghosttyTheme.foreground.opacity(0.88)
                )
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            if let trailing {
                Text(trailing)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(ghosttyTheme.tertiaryText)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    // MARK: - Files

    private var filesSection: some View {
        let isEmpty = overlayFiles.isEmpty && externalFiles.isEmpty
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                sectionLabel("Files")
                Spacer(minLength: 0)
                Button {
                    activities.openFiles()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ghosttyTheme.secondaryText)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open Files")
                .accessibilityLabel("Open Files")
            }

            if isEmpty {
                Text("None")
                    .font(.system(size: 12))
                    .foregroundStyle(ghosttyTheme.tertiaryText)
                    .padding(.vertical, 3)
            } else {
                ForEach(overlayFiles) { session in
                    overlaySessionRow(session, systemImage: "folder")
                }
                ForEach(externalFiles) { activity in
                    externalActivityRow(activity, systemImage: "folder")
                }
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Rename

    private func beginRename(_ target: GlanceRenameTarget, current: String) {
        renameDraft = current
        renameTarget = target
    }

    private func applyRename() {
        defer { renameTarget = nil }
        guard let renameTarget else { return }
        switch renameTarget {
        case .overlay(let id):
            activities.renameOverlay(id, title: renameDraft)
        case .external(let id):
            activities.renameExternal(id, label: renameDraft)
        }
    }

    // MARK: - Chrome

    @ViewBuilder
    private var cardVeil: some View {
        if preferences.preferences.chromeGlass {
            ZStack {
                ghosttyTheme.panel.opacity(0.16)
                Color.clear
                    .glassEffect(
                        .clear.tint(ghosttyTheme.panel.opacity(0.24)),
                        in: cardShape
                    )
            }
        } else {
            ZStack {
                ChromeGlassBackground(
                    tintColor: NSColor(ghosttyTheme.panel).withAlphaComponent(0.26),
                    cornerRadius: cornerRadius
                )
                ghosttyTheme.panel.opacity(0.30)
            }
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(ghosttyTheme.foreground.opacity(0.10))
            .frame(height: 1)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(ghosttyTheme.secondaryText.opacity(0.92))
    }

    private func displayTitle(for session: OverlaySession) -> String {
        var title = session.title
        for prefix in ["BG: ", "Editor: ", "ED: "] {
            if title.hasPrefix(prefix) {
                title = String(title.dropFirst(prefix.count))
                break
            }
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            switch session.kind {
            case .editor: return "editor"
            case .files: return "files"
            case .background: return "shell"
            }
        }
        return trimmed
    }
}

private enum GlanceRenameTarget: Identifiable, Equatable {
    case overlay(UUID)
    case external(UUID)

    var id: String {
        switch self {
        case .overlay(let id): return "o-\(id.uuidString)"
        case .external(let id): return "e-\(id.uuidString)"
        }
    }
}

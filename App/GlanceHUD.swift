import AppKit
import SwiftUI

/// Glance — Activity Manager UI (ADR 0023).
///
/// Compact inventory of Activities for the focused Worktree: Changes, Shells, Editors, Files.
/// Overlay Activities support Focus (peek) / Hide; External Activities come later (Focus / End).
struct GlanceHUD: View {
    @EnvironmentObject private var overlays: OverlayController
    @EnvironmentObject private var preferences: PreferencesController
    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme

    private let cardWidth: CGFloat = 240
    private let cornerRadius: CGFloat = 16

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    /// Prototype placeholders until git overview is wired.
    private let prototypeInserted = 12
    private let prototypeDeleted = 3

    /// Shell Activities with Overlay Presentation (Background CLIs).
    private var shells: [OverlaySession] {
        overlays.focusedSessions.filter { $0.kind == .background }
    }

    /// Editor Activities with Overlay Presentation.
    private var editors: [OverlaySession] {
        overlays.focusedSessions.filter { $0.kind == .editor }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            changesSection
            sectionDivider
            categorySection(
                title: "Shells",
                systemImage: "terminal",
                sessions: shells,
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
                sessions: editors,
                emptyLabel: "None",
                addAction: {
                    overlays.openEditor()
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
    }

    // MARK: - Changes

    private var changesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Changes")

            HStack(spacing: 8) {
                Text("+\(prototypeInserted)")
                    .foregroundStyle(Color(red: 0.45, green: 0.78, blue: 0.52))
                Text("−\(prototypeDeleted)")
                    .foregroundStyle(Color(red: 0.92, green: 0.45, blue: 0.45))
                Spacer(minLength: 0)
            }
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .padding(.vertical, 1)
        }
        .padding(.bottom, 12)
    }

    // MARK: - Category (Shells / Editors)

    private func categorySection(
        title: String,
        systemImage: String,
        sessions: [OverlaySession],
        emptyLabel: String,
        addAction: (() -> Void)?,
        addHelp: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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

            if sessions.isEmpty {
                Text(emptyLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(ghosttyTheme.tertiaryText)
                    .padding(.vertical, 3)
            } else {
                ForEach(sessions) { session in
                    sessionRow(session, systemImage: systemImage)
                }
            }
        }
        .padding(.vertical, 12)
    }

    private func sessionRow(_ session: OverlaySession, systemImage: String) -> some View {
        let isFocused = overlays.visibleOverlayID == session.id
        return Button {
            if isFocused {
                overlays.hide()
            } else {
                overlays.peek(session.id)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(
                        isFocused
                            ? ghosttyTheme.foreground.opacity(0.9)
                            : ghosttyTheme.secondaryText
                    )
                    .frame(width: 14, alignment: .center)

                Text(displayTitle(for: session))
                    .font(.system(size: 12, weight: isFocused ? .medium : .regular))
                    .foregroundStyle(
                        isFocused
                            ? ghosttyTheme.foreground
                            : ghosttyTheme.foreground.opacity(0.88)
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isFocused ? "Hide (keeps running)" : "Focus")
    }

    // MARK: - Files (future External / Overlay file manager)

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Files")

            HStack(spacing: 8) {
                Image(systemName: "doc")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(ghosttyTheme.tertiaryText)
                    .frame(width: 14, alignment: .center)

                Text("None")
                    .font(.system(size: 12))
                    .foregroundStyle(ghosttyTheme.tertiaryText)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
        }
        .padding(.top, 12)
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

    /// Plain row label — category is the section; Presentation is Overlay today.
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
            return session.kind == .editor ? "editor" : "shell"
        }
        return trimmed
    }
}

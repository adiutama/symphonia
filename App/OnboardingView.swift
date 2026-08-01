import SwiftUI

/// Stepped first-launch welcome — tour pages, then Tools preferences (ADR 2026-07-31-0023-activity-manager-overlay-presentation).
struct OnboardingView: View {
    @EnvironmentObject private var preferences: PreferencesController
    @EnvironmentObject private var settingsNavigation: SettingsNavigation
    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme

    @State private var stepIndex = 0

    private let pages: [OnboardingPage] = [
        .tour(
            gifName: "onboarding-welcome",
            symbol: "music.quarternote.3",
            title: "Welcome to Symphonia",
            body: "You and your coding agents share one stage. We built Symphonia so you can conduct them without the usual chaos of tabs, clones, and colliding shortcuts."
        ),
        .tour(
            gifName: "onboarding-workspace",
            symbol: "square.stack.3d.up",
            title: "Workspaces and Worktrees",
            body: "Juggling branches and folders for agents gets messy fast. A Workspace keeps your Main Repo and Worktrees together as siblings, so each lane stays clear."
        ),
        .tour(
            gifName: "onboarding-main-cli",
            symbol: "terminal",
            title: "Main CLI is home",
            body: "Your agent lives in the Main CLI. Need an editor, shell, or files? Open them from Glance — Overlay peeks on top of Main, or an External GUI when you choose one. Hide an Overlay when you are done; End tears it down."
        ),
        .tour(
            gifName: "onboarding-secrets",
            symbol: "key.fill",
            title: "Secret Store",
            body: "Managing secrets and env vars is a struggle. We made it easy with a Workspace Secret Store. No more copy-pasting .env files every time you create a Worktree. Symphonia injects what you enable into your CLIs."
        ),
        .tour(
            gifName: "onboarding-command-center",
            symbol: "command",
            title: "Command Center",
            body: "App shortcuts and agent keybinds used to fight over the same keys. Press Leader (⌘⇧P by default) when you want Symphonia to listen. Sequences and hotkeys stay out of the terminal’s way."
        ),
        .tools,
        .tour(
            gifName: "onboarding-ready",
            symbol: "sparkles",
            title: "Make the stage yours",
            body: "New Workspaces land under a Workspaces Root you can change in Settings. Prefer another folder for one project? Give that Workspace its own Prefix. Then create a Workspace and start composing."
        ),
    ]

    private var isLastStep: Bool {
        stepIndex >= pages.count - 1
    }

    private var currentPage: OnboardingPage {
        pages[stepIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            footer
                .padding(.top, 16)
        }
        .padding(24)
        .frame(width: 560, height: currentPage.isTools ? 560 : 520)
        .background(ghosttyTheme.background)
        .onAppear {
            seedToolDefaultsIfNeeded()
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch currentPage {
        case let .tour(gifName, symbol, title, body):
            tourContent(gifName: gifName, symbol: symbol, title: title, body: body)
        case .tools:
            toolsContent
        }
    }

    private func tourContent(gifName: String, symbol: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            mediaFrame(gifName: gifName, symbol: symbol, accessibilityTitle: title)

            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(ghosttyTheme.foreground)
                .fixedSize(horizontal: false, vertical: true)

            Text(body)
                .font(.body)
                .foregroundStyle(ghosttyTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .id(stepIndex)
        .transition(stepTransition)
        .animation(.easeInOut(duration: 0.2), value: stepIndex)
    }

    private var toolsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your tools")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(ghosttyTheme.foreground)

                Text("Tell Symphonia how you open craft surfaces. No guessing from $EDITOR — you can change this anytime in Settings → Tools.")
                    .font(.body)
                    .foregroundStyle(ghosttyTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                ActivitySettingsSection(
                    title: "Editor",
                    systemImage: "pencil",
                    blurb: "TUI peeks as Overlay. GUI launches External (Focus / End). Folder-capable: Cursor, VS Code, Zed, Xcode…",
                    badge: nil
                ) {
                    ActivityPresentationConfigurator(
                        presentation: editorPresentationBinding,
                        command: $preferences.preferences.editorCommand,
                        bundleID: $preferences.preferences.editorBundleID,
                        commandPlaceholder: "vi · $EDITOR",
                        commandDetail: "Empty uses $VISUAL / $EDITOR, then vi.",
                        bundlePlaceholder: ActivityDefaults.editorBundleID,
                        bundleDetail: "TextEdit is always available. Prefer Cursor/VS Code/Zed to open the Worktree folder."
                    )
                }

                ActivitySettingsSection(
                    title: "Files",
                    systemImage: "folder",
                    blurb: "Default Finder (External). TUI opens a file-manager Overlay.",
                    badge: nil
                ) {
                    ActivityPresentationConfigurator(
                        presentation: $preferences.preferences.fileManagerPresentation,
                        command: $preferences.preferences.fileManagerCommand,
                        bundleID: $preferences.preferences.fileManagerBundleID,
                        commandPlaceholder: "Command",
                        commandDetail: "Empty opens a bare shell Overlay.",
                        bundlePlaceholder: ActivityDefaults.fileManagerBundleID,
                        bundleDetail: "Stock default is Finder."
                    )
                }
            }
        }
        .id(stepIndex)
        .transition(stepTransition)
        .animation(.easeInOut(duration: 0.2), value: stepIndex)
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity.combined(with: .move(edge: .leading))
        )
    }

    private var editorPresentationBinding: Binding<EditorPresentation> {
        Binding(
            get: {
                preferences.preferences.editorPresentation
                    ?? preferences.effective.editorPresentation
            },
            set: { newValue in
                preferences.preferences.editorPresentation = newValue
                if newValue == .externalApp {
                    if preferences.preferences.editorBundleID
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                    {
                        preferences.preferences.editorBundleID = ActivityDefaults.editorBundleID
                    }
                    // Operator chose GUI knowingly during onboarding.
                    preferences.preferences.hasSeenExternalEditorReminder = true
                }
            }
        )
    }

    @ViewBuilder
    private func mediaFrame(gifName: String, symbol: String, accessibilityTitle: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(ghosttyTheme.panel)

            if AnimatedGIFView.hasGIF(named: gifName) {
                AnimatedGIFView(resourceName: gifName)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(ghosttyTheme.accent)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .accessibilityLabel(accessibilityTitle)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            stepDots

            Spacer(minLength: 8)

            if stepIndex > 0 {
                Button("Back") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        stepIndex -= 1
                    }
                }
                .keyboardShortcut(.cancelAction)
            }

            if isLastStep {
                Button("Open Settings…") {
                    finish(openSettings: true)
                }
                Button("Get started") {
                    finish(openSettings: false)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            } else {
                Button("Continue") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        stepIndex += 1
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(pages.indices, id: \.self) { index in
                Circle()
                    .fill(index == stepIndex ? ghosttyTheme.accent : ghosttyTheme.tertiaryText.opacity(0.55))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(stepIndex + 1) of \(pages.count)")
    }

    /// Persist explicit Presentation so Effective Setting never falls back to basename heuristics.
    private func seedToolDefaultsIfNeeded() {
        if preferences.preferences.editorPresentation == nil {
            preferences.preferences.editorPresentation = .terminalOverlay
        }
        if preferences.preferences.editorBundleID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        {
            preferences.preferences.editorBundleID = ActivityDefaults.editorBundleID
        }
        if preferences.preferences.fileManagerBundleID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        {
            preferences.preferences.fileManagerBundleID = ActivityDefaults.fileManagerBundleID
        }
    }

    private func finish(openSettings: Bool) {
        seedToolDefaultsIfNeeded()
        preferences.preferences.onboardingCompleted = true
        preferences.save()
        if openSettings {
            settingsNavigation.open(.globalTools)
        }
    }
}

private enum OnboardingPage {
    case tour(gifName: String, symbol: String, title: String, body: String)
    case tools

    var isTools: Bool {
        if case .tools = self { return true }
        return false
    }
}

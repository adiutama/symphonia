import SwiftUI

/// Stepped first-launch welcome — one idea per page, GIF “video” when bundled.
struct OnboardingView: View {
    @EnvironmentObject private var preferences: PreferencesController
    @EnvironmentObject private var settingsNavigation: SettingsNavigation
    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme

    @State private var stepIndex = 0

    private let steps: [OnboardingStep] = [
        // Obvious → niche: stage, projects, terminal, secrets, Leader, then personalize.
        OnboardingStep(
            gifName: "onboarding-welcome",
            symbol: "music.quarternote.3",
            title: "Welcome to Symphonia",
            body: "You and your coding agents share one stage. We built Symphonia so you can conduct them without the usual chaos of tabs, clones, and colliding shortcuts."
        ),
        OnboardingStep(
            gifName: "onboarding-workspace",
            symbol: "square.stack.3d.up",
            title: "Workspaces and Worktrees",
            body: "Juggling branches and folders for agents gets messy fast. A Workspace keeps your Main Repo and Worktrees together as siblings, so each lane stays clear."
        ),
        OnboardingStep(
            gifName: "onboarding-main-cli",
            symbol: "terminal",
            title: "Main CLI is home",
            body: "Your agent lives in the Main CLI. Need an editor or a shell? Open an Activity — Overlay peeks on top of Main, or an External GUI when you choose one. Hide an Overlay when you are done; the process keeps running until you End it."
        ),
        OnboardingStep(
            gifName: "onboarding-secrets",
            symbol: "key.fill",
            title: "Secret Store",
            body: "Managing secrets and env vars is a struggle. We made it easy with a Workspace Secret Store. No more copy-pasting .env files every time you create a Worktree. Symphonia injects what you enable into your CLIs."
        ),
        OnboardingStep(
            gifName: "onboarding-command-center",
            symbol: "command",
            title: "Command Center",
            body: "App shortcuts and agent keybinds used to fight over the same keys. Press Leader (⌘⇧P by default) when you want Symphonia to listen. Sequences and hotkeys stay out of the terminal’s way."
        ),
        OnboardingStep(
            gifName: "onboarding-ready",
            symbol: "sparkles",
            title: "Make the stage yours",
            body: "New Workspaces land under a Workspaces Root you can change in Settings. Prefer another folder for one project? Give that Workspace its own Prefix. Then create a Workspace and start composing."
        ),
    ]

    private var isLastStep: Bool {
        stepIndex >= steps.count - 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            footer
                .padding(.top, 16)
        }
        .padding(24)
        .frame(width: 520, height: 520)
        .background(ghosttyTheme.background)
    }

    private var stepContent: some View {
        let step = steps[stepIndex]
        return VStack(alignment: .leading, spacing: 16) {
            mediaFrame(for: step)

            Text(step.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(ghosttyTheme.foreground)
                .fixedSize(horizontal: false, vertical: true)

            Text(step.body)
                .font(.body)
                .foregroundStyle(ghosttyTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .id(stepIndex)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity.combined(with: .move(edge: .leading))
        ))
        .animation(.easeInOut(duration: 0.2), value: stepIndex)
    }

    @ViewBuilder
    private func mediaFrame(for step: OnboardingStep) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(ghosttyTheme.panel)

            if AnimatedGIFView.hasGIF(named: step.gifName) {
                AnimatedGIFView(resourceName: step.gifName)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Image(systemName: step.symbol)
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(ghosttyTheme.accent)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .accessibilityLabel(step.title)
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
                Button("Choose Workspace path…") {
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
            ForEach(steps.indices, id: \.self) { index in
                Circle()
                    .fill(index == stepIndex ? ghosttyTheme.accent : ghosttyTheme.tertiaryText.opacity(0.55))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(stepIndex + 1) of \(steps.count)")
    }

    private func finish(openSettings: Bool) {
        preferences.preferences.onboardingCompleted = true
        preferences.save()
        if openSettings {
            settingsNavigation.openSettings()
        }
    }
}

private struct OnboardingStep {
    /// Basename under `App/OnboardingMedia/<name>.gif`.
    let gifName: String
    let symbol: String
    let title: String
    let body: String
}

import AppKit
import SwiftUI

/// Floating Glance chip (option B) — content-sized glass card under the titlebar
/// toggle, layered over Main CLI. Not a sidebar rail.
///
/// Overlays are the first module. Git / other modules deferred.
struct GlanceHUD: View {
    @EnvironmentObject private var overlays: OverlayController
    @EnvironmentObject private var preferences: PreferencesController
    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme

    private let chipWidth: CGFloat = 160
    private let emptyMinHeight: CGFloat = 72
    private let cornerRadius: CGFloat = 10

    private var chipShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var isEmpty: Bool {
        overlays.focusedSessions.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            overlaysSection
            // Future modules (git overview, …) stack here.
        }
        .padding(9)
        .frame(width: chipWidth, alignment: .topLeading)
        .frame(minHeight: isEmpty ? emptyMinHeight : nil, alignment: .topLeading)
        .background { chipVeil }
        .clipShape(chipShape)
        // Soft lift only — no stroke / glass rim.
        .shadow(color: .black.opacity(0.38), radius: 22, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Glance")
    }

    /// Translucent blur over Main CLI — lighter than Command Center panels, no border.
    @ViewBuilder
    private var chipVeil: some View {
        if preferences.preferences.chromeGlass {
            ZStack {
                ghosttyTheme.panel.opacity(0.14)
                Color.clear
                    .glassEffect(
                        .clear.tint(ghosttyTheme.panel.opacity(0.2)),
                        in: chipShape
                    )
            }
        } else {
            // Still translucent when glass chrome is off — Glance should read as a HUD.
            ZStack {
                ChromeGlassBackground(
                    tintColor: NSColor(ghosttyTheme.panel).withAlphaComponent(0.22),
                    cornerRadius: cornerRadius
                )
                ghosttyTheme.panel.opacity(0.24)
            }
        }
    }

    // MARK: - Overlays

    private var overlaysSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("OVERLAYS")

            if overlays.focusedSessions.isEmpty {
                Text("None")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(ghosttyTheme.tertiaryText.opacity(0.85))
                    .padding(.leading, 2)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            } else {
                ForEach(Array(overlays.focusedSessions.enumerated()), id: \.element.id) { index, session in
                    overlayRow(session, index: index + 1)
                }
            }
        }
    }

    private func overlayRow(_ session: OverlaySession, index: Int) -> some View {
        let isVisible = overlays.visibleOverlayID == session.id
        return Button {
            if isVisible {
                overlays.hide()
            } else {
                overlays.peek(session.id)
            }
        } label: {
            HStack(alignment: .center, spacing: 7) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(
                        isVisible
                            ? ghosttyTheme.accent.opacity(0.95)
                            : ghosttyTheme.foreground.opacity(0.18)
                    )
                    .frame(width: 3, height: 20)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(String(format: "%02d", index))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(ghosttyTheme.tertiaryText)
                        Text(session.kind == .editor ? "ED" : "BG")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(ghosttyTheme.secondaryText)
                    }
                    Text(session.title)
                        .font(.system(size: 11, weight: isVisible ? .semibold : .regular))
                        .foregroundStyle(
                            isVisible
                                ? ghosttyTheme.foreground
                                : ghosttyTheme.foreground.opacity(0.72)
                        )
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .opacity(isVisible ? 1 : 0.82)
        }
        .buttonStyle(.plain)
        .help(session.kind == .editor ? "Peek Editor" : "Peek Background")
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(ghosttyTheme.secondaryText.opacity(0.9))
            .tracking(0.8)
            .padding(.leading, 2)
    }
}

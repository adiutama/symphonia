import SwiftUI

/// Supacode-inspired Settings chrome: page title → section header → card → rows.
/// Surfaces and fields pull from ``GhosttyChromeTheme`` so chrome matches the terminal.

struct SettingsPage<Content: View>: View {
    let title: String
    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(ghosttyTheme.foreground)
                    .padding(.bottom, 4)

                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(ghosttyTheme.foreground)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsCard<Content: View>: View {
    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ghosttyTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SettingsRow<Control: View>: View {
    let title: String
    let description: String?
    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme
    @ViewBuilder var control: () -> Control

    init(title: String, description: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.description = description
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(ghosttyTheme.foreground)
                if let description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(ghosttyTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            control()
                .frame(minWidth: 160, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

/// Soft row separator — opacity fade, not a hard rule.
struct SettingsRowDivider: View {
    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme

    var body: some View {
        LinearGradient(
            colors: [
                ghosttyTheme.hairline.opacity(0),
                ghosttyTheme.hairline.opacity(0.55),
                ghosttyTheme.hairline.opacity(0.55),
                ghosttyTheme.hairline.opacity(0),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
        .padding(.horizontal, 14)
    }
}

/// Soft horizontal rule that fades at the ends.
struct SoftHairline: View {
    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme
    var horizontalPadding: CGFloat = 0

    var body: some View {
        LinearGradient(
            colors: [
                ghosttyTheme.hairline.opacity(0),
                ghosttyTheme.hairline.opacity(0.45),
                ghosttyTheme.hairline.opacity(0.45),
                ghosttyTheme.hairline.opacity(0),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
        .padding(.horizontal, horizontalPadding)
    }
}

/// Plain text field filled with Ghostty `control` so it contrasts against Settings cards.
struct SettingsControlFieldModifier: ViewModifier {
    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(ghosttyTheme.control)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

extension View {
    /// Theme-matched Settings text field (replaces `.roundedBorder` system chrome).
    func settingsControlField() -> some View {
        modifier(SettingsControlFieldModifier())
    }
}

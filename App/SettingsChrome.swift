import SwiftUI

/// Supacode-inspired Settings chrome: page title → section header → card → rows.
/// Surfaces and fields pull from ``GhosttyChromeTheme`` so chrome matches the terminal.

struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.primary)
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
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

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
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct SettingsRow<Control: View>: View {
    let title: String
    let description: String?
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
                    .foregroundStyle(.primary)
                if let description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

/// Hairline between rows inside a `SettingsCard`.
struct SettingsRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, 14)
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

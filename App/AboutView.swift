import AppKit
import SwiftUI

/// Small About window: version, positioning, license, and upstream credit.
struct AboutView: View {
    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme
    @Environment(\.dismiss) private var dismiss

    private var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Symphonia")
                        .font(.title.weight(.bold))
                    Text(SymphoniaBrand.tagline)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("Version \(shortVersion) (\(buildVersion))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }

            Text(SymphoniaBrand.description)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            SettingsCard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("License")
                            .font(.body.weight(.medium))
                        Spacer()
                        Text("MIT")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    SettingsRowDivider()
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Terminal")
                            .font(.body.weight(.medium))
                        Text("Ghostty / libghostty (MIT)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }

            Text("Copyright © 2026 Adi Utama and Symphonia contributors")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(ghosttyTheme.background)
    }
}

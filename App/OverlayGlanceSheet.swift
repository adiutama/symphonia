import SwiftUI

/// Overlay list that sits in the main pane’s trailing edge (same surface as the terminal host).
struct OverlayGlanceSheet: View {
    @EnvironmentObject private var overlays: OverlayController
    @EnvironmentObject private var workspaces: WorkspaceController
    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme

    private let railWidth: CGFloat = 260

    var body: some View {
        Group {
            if overlays.focusedSessions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(overlays.focusedSessions) { session in
                            overlayRow(session)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(width: railWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ghosttyTheme.background)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(headerTitle)
    }

    private var headerTitle: String {
        if let slug = workspaces.current?.slug {
            return "Overlays · \(displayLowercased(slug))"
        }
        return "Overlays"
    }

    private var emptyState: some View {
        Text("No overlays")
            .font(.callout)
            .foregroundStyle(ghosttyTheme.tertiaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 16)
            .padding(.top, 16)
    }

    private func overlayRow(_ session: OverlaySession) -> some View {
        let isVisible = overlays.visibleOverlayID == session.id
        return Button {
            if isVisible {
                overlays.hide()
            } else {
                overlays.peek(session.id)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: session.kind == .editor ? "chevron.left.forwardslash.chevron.right" : "terminal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ghosttyTheme.secondaryText)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title)
                        .font(.callout)
                        .foregroundStyle(ghosttyTheme.foreground)
                        .lineLimit(1)
                    Text(session.kind == .editor ? "Editor" : "Background")
                        .font(.caption2)
                        .foregroundStyle(ghosttyTheme.tertiaryText)
                }

                Spacer(minLength: 8)

                if isVisible {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ghosttyTheme.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(isVisible ? ghosttyTheme.selectionFill : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var commandMode: CommandModeController
    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme
    @EnvironmentObject private var preferences: PreferencesController

    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 240
    @State private var dragStartWidth: Double?

    private let sidebarMinWidth: Double = 180
    private let sidebarMaxWidth: Double = 400

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                WorkspaceSidebarView()
                    .frame(width: sidebarWidth)
                    .overlay(alignment: .trailing) {
                        SoftPaneHairline()
                    }
                    .overlay(alignment: .trailing) {
                        resizeHandle
                    }

                OverlayHostView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 720, minHeight: 420)

            if commandMode.isActive {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture {
                        commandMode.dismiss()
                    }

                CommandModeView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        // When glass is on, keep the window clear under the sidebar so Liquid Glass /
        // vibrancy can sample the desktop. The terminal host paints its own solid fill.
        .background {
            if preferences.preferences.chromeGlass {
                Color.clear
            } else {
                ghosttyTheme.background
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .symphoniaTitlebarChrome()
        .animation(.easeOut(duration: 0.12), value: commandMode.isActive)
        .background(SettingsWindowPresenter())
        .sheet(isPresented: Binding(
            get: { !preferences.preferences.onboardingCompleted },
            set: { presented in
                if !presented {
                    preferences.preferences.onboardingCompleted = true
                    preferences.save()
                }
            }
        )) {
            OnboardingView()
        }
    }

    /// Invisible resize hit-target on the sidebar’s trailing edge (no gap / seam in the HStack).
    private var resizeHandle: some View {
        Color.clear
            .frame(width: 8)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let base = dragStartWidth ?? sidebarWidth
                        if dragStartWidth == nil {
                            dragStartWidth = base
                        }
                        let proposed = base + value.translation.width
                        sidebarWidth = min(max(proposed, sidebarMinWidth), sidebarMaxWidth)
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                    }
            )
    }
}

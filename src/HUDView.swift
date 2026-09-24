import SwiftUI

enum SceneID {
    static let main = "main"
    static let hud = "hud"
}

/// The floating HUD's visibility, shared by the dashboard button, Settings, and the HUD's own menu.
enum HUD {
    static let visibilityKey = "showMiniHUD"

    static func setVisible(_ visible: Bool, open: OpenWindowAction, dismiss: DismissWindowAction) {
        UserDefaults.standard.set(visible, forKey: visibilityKey)
        if visible { open(id: SceneID.hud) } else { dismiss(id: SceneID.hud) }
    }
}

/// A tiny always-on-top readout. Drag to move; right-click for options.
struct MiniHUDView: View {
    @Environment(MonitorViewModel.self) private var vm
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 16) {
                metric("CPU", vm.glance.cpu, Theme.loadColor(Double(vm.glance.cpu)))
                metric("MEM", vm.glance.memory, Theme.color(for: vm.memoryPressure))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .glassEffect(.regular, in: .capsule)
        .fixedSize()
        .contextMenu {
            Button("Open Dashboard") {
                NSApp.activate()
                openWindow(id: SceneID.main)
            }
            Button("Hide HUD") {
                HUD.setVisible(false, open: openWindow, dismiss: dismissWindow)
            }
        }
        .background(WindowAccessor { window in
            // Transparent so only the glass capsule shows; its own shadow follows the capsule.
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            // Stay put on every Space, over full-screen apps, and out of ⌘` / the Window menu.
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isExcludedFromWindowsMenu = true
        })
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Resource Tracker HUD")
        .onAppear { vm.setVisible(.hud, true) }
        .onDisappear { vm.setVisible(.hud, false) }
    }

    /// Numbers stay primary so they read over any wallpaper or window (coloured text on
    /// glass loses contrast); status colour rides on the dot beside the label.
    private func metric(_ label: String, _ percent: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            Text("\(percent)%").font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(.primary)
        }
    }
}

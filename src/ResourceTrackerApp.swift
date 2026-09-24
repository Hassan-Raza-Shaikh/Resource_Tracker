import SwiftUI

@main
struct ResourceTrackerApp: App {
    @State private var vm = MonitorViewModel()

    var body: some Scene {
        // `Window`, not `WindowGroup`: one dashboard. openWindow(id:) brings it back if closed.
        Window("Resource Tracker", id: SceneID.main) {
            ContentView()
                .environment(vm)
        }
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 1000, height: 720)

        Window("HUD", id: SceneID.hud) {
            MiniHUDView()
                .environment(vm)
        }
        .windowStyle(.plain)
        .windowLevel(.floating)
        .windowResizability(.contentSize)
        .windowBackgroundDragBehavior(.enabled)
        // Reopened at launch by the dashboard when the preference is on (see ContentView).
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        .defaultWindowPlacement { content, context in
            let size = content.sizeThatFits(.unspecified)
            let screen = context.defaultDisplay.visibleRect
            return WindowPlacement(CGPoint(x: screen.maxX - size.width - 24, y: screen.maxY - size.height - 24), size: size)
        }

        MenuBarExtra("Resource Tracker", systemImage: "chart.bar.fill") {
            MenuBarView()
                .environment(vm)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

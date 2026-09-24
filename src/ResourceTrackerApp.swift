import SwiftUI

@main
struct ResourceTrackerApp: App {
    @State private var vm = MonitorViewModel()
    // Owned here, not by a view, so a test keeps running (and its result survives) when you switch tabs.
    @State private var speedTest = SpeedTest()
    @State private var diagnostics = NetworkDiagnostics()

    var body: some Scene {
        // `Window`, not `WindowGroup`: one dashboard. openWindow(id:) brings it back if closed.
        Window("Resource Tracker", id: SceneID.main) {
            ContentView()
                .environment(vm)
                .environment(speedTest)
                .environment(diagnostics)
        }
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 1000, height: 720)
        // Unit tests run inside the app; don't put the dashboard on screen while they do.
        .defaultLaunchBehavior(Self.isRunningTests ? .suppressed : .automatic)

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

        MenuBarExtra {
            MenuBarView()
                .environment(vm)
        } label: {
            // The app icon's gauge-and-pulse mark, as a template image that macOS tints
            // for light and dark menu bars.
            Image("MenuBarIcon")
                .accessibilityLabel("Resource Tracker")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }

    private static let isRunningTests = ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"]
        .contains { ProcessInfo.processInfo.environment[$0] != nil }
}

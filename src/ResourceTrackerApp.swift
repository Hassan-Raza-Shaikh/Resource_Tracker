import SwiftUI

@main
struct ResourceTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 850, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

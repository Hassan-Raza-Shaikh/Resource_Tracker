import SwiftUI
import ServiceManagement

struct MenuWidgetView: View {
    @EnvironmentObject var vm: MonitorViewModel
    
    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Image(systemName: "cpu")
                        .foregroundColor(.accentColor)
                    Text("Resource Tracker")
                        .font(.headline)
                    Spacer()
                    Button(action: {
                        NSApp.activate(ignoringOtherApps: true)
                        for window in NSApplication.shared.windows {
                            window.makeKeyAndOrderFront(nil)
                        }
                    }) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.plain)
                    .help("Open Full Dashboard")
                }
                
                Divider()
                
                // Mini Stats
                HStack(spacing: 20) {
                    VStack(alignment: .leading) {
                        Text("CPU").font(.caption).foregroundColor(.secondary)
                        Text(String(format: "%.1f%%", vm.displayCpu))
                            .font(.system(.body, design: .rounded))
                            .bold()
                            .foregroundColor(Theme.statusColor(pressure: vm.displayCpu))
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Memory").font(.caption).foregroundColor(.secondary)
                        Text(String(format: "%.1f%%", vm.displayMemPressure))
                            .font(.system(.body, design: .rounded))
                            .bold()
                            .foregroundColor(Theme.statusColor(pressure: vm.displayMemPressure))
                    }
                    
                    VStack(alignment: .leading) {
                        Text("GPU").font(.caption).foregroundColor(.secondary)
                        Text(String(format: "%.1f%%", vm.displayGpu))
                            .font(.system(.body, design: .rounded))
                            .bold()
                            .foregroundColor(Theme.amethyst)
                    }
                }
                
                Divider()
                
                HStack {
                    Button("Settings") {
                        if #available(macOS 14.0, *) {
                            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    
                    Spacer()
                    
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }
            .padding(16)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .presentationBackground(.clear)
        .frame(width: 250)
    }
}

// MARK: - Mini HUD View
struct MiniHUDView: View {
    @EnvironmentObject var vm: MonitorViewModel
    
    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CPU").font(.system(size: 9)).foregroundColor(.secondary)
                    Text(String(format: "%.0f%%", vm.displayCpu)).font(.system(size: 12, design: .rounded)).bold().foregroundColor(Theme.statusColor(pressure: vm.displayCpu))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("MEM").font(.system(size: 9)).foregroundColor(.secondary)
                    Text(String(format: "%.0f%%", vm.displayMemPressure)).font(.system(size: 12, design: .rounded)).bold().foregroundColor(Theme.statusColor(pressure: vm.displayMemPressure))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .glassEffect(.regular, in: .capsule)
        .presentationBackground(.clear)
        .frame(width: 130, height: 40)
        // Make it float and draggable
        .background(WindowAccessor { window in
            window.level = .floating // Always on top
            window.styleMask = [.borderless]
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            window.isMovableByWindowBackground = true
        })
    }
}

@main
struct ResourceTrackerApp: App {
    @StateObject private var vm = MonitorViewModel()
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showMiniHUD") private var showMiniHUD = false

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(vm)
                .frame(minWidth: 900, minHeight: 650)
        }
        .windowStyle(.hiddenTitleBar)
        
        WindowGroup(id: "hud") {
            MiniHUDView()
                .environmentObject(vm)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 120, height: 40)
        .defaultPosition(.bottomTrailing)
        
        MenuBarExtra("Resource Tracker", systemImage: "chart.bar.fill") {
            MenuWidgetView()
                .environmentObject(vm)
        }
        .menuBarExtraStyle(.window)
        
        Settings {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showMiniHUD") private var showMiniHUD = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Resource Tracker Settings").font(.title2).bold()
            
            Form {
                Toggle("Launch at Login", isOn: Binding(
                    get: { self.launchAtLogin },
                    set: { newValue in
                        self.launchAtLogin = newValue
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            print("Failed to update Launch at Login: \(error)")
                            self.launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                ))
                
                Toggle("Show Always-On-Top HUD", isOn: Binding(
                    get: { self.showMiniHUD },
                    set: { newValue in
                        self.showMiniHUD = newValue
                        if newValue {
                            openWindow(id: "hud")
                            // Ensure it comes to front
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                NSApp.windows.first { $0.title == "hud" }?.makeKeyAndOrderFront(nil)
                            }
                        } else {
                            // Hide the HUD window
                            NSApp.windows.forEach { window in
                                if window.styleMask.contains(.borderless) && window.level == .floating {
                                    window.close()
                                }
                            }
                        }
                    }
                ))
            }
            Spacer()
        }
        .padding(30)
        .frame(width: 400, height: 250)
    }
}

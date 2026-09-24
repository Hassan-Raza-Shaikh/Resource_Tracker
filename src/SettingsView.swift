import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage(HUD.visibilityKey) private var showHUD = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    /// Read from the system rather than stored: the user can change it in System Settings at any time.
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                    set: setOpenAtLogin
                ))
                if loginStatus == .requiresApproval {
                    LabeledContent {
                        Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                    } label: {
                        Text("Allow Resource Tracker in System Settings to finish turning this on.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(Theme.alert)
                }
            }

            Section {
                Toggle("Show floating HUD", isOn: Binding(
                    get: { showHUD },
                    set: { HUD.setVisible($0, open: openWindow, dismiss: dismissWindow) }
                ))
            } footer: {
                Text("A small always-on-top readout of CPU and memory that stays visible over full-screen apps. Drag it anywhere; right-click it for options.")
            }

            Section {
                LabeledContent("Version", value: Self.version)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = SMAppService.mainApp.status
        }
    }

    private func setOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Couldn’t update login item: \(error.localizedDescription)"
        }
        loginStatus = SMAppService.mainApp.status
    }

    private static let version: String = {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }()
}

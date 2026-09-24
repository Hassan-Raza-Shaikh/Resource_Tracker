import SwiftUI

/// The menu bar extra: an at-a-glance summary with shortcuts into the app.
struct MenuBarView: View {
    @Environment(MonitorViewModel.self) private var vm
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Theme.color(for: vm.status.level))
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(vm.status.text)
                        .font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                    GridRow {
                        stat("CPU", "\(vm.glance.cpu)%", Theme.loadColor(Double(vm.glance.cpu)))
                        stat("Memory", "\(vm.glance.memory)%", Theme.color(for: vm.memoryPressure))
                        stat("GPU", "\(vm.glance.gpu)%", Theme.amethyst)
                    }
                    GridRow {
                        stat("Download", vm.glance.download, Theme.ocean)
                        stat("Upload", vm.glance.upload, Theme.rose)
                            .gridCellColumns(2)
                    }
                }

                Divider()

                VStack(spacing: 2) {
                    menuButton("Open Dashboard", systemImage: "macwindow") {
                        NSApp.activate()
                        openWindow(id: SceneID.main)
                    }
                    menuButton("Settings…", systemImage: "gearshape") {
                        NSApp.activate()
                        openSettings()
                    }
                    menuButton("Quit Resource Tracker", systemImage: "power") {
                        NSApp.terminate(nil)
                    }
                }
            }
            .padding(16)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .presentationBackground(.clear)
        .frame(width: 280)
        .onAppear { vm.setVisible(.menuBar, true) }
        .onDisappear { vm.setVisible(.menuBar, false) }
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).metricFont(.body).foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
    }

    private func menuButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
                .padding(.vertical, 5)
                .padding(.horizontal, 6)
        }
        .buttonStyle(MenuRowButtonStyle())
    }
}

/// Highlights on hover like a native menu item.
private struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuRow(configuration: configuration)
    }

    private struct MenuRow: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .background(Color.primary.opacity(configuration.isPressed ? 0.12 : (isHovering ? 0.07 : 0)),
                            in: .rect(cornerRadius: 6))
                .onHover { isHovering = $0 }
        }
    }
}

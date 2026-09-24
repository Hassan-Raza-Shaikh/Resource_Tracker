import SwiftUI

// MARK: - Navigation

enum Tab: String, CaseIterable, Identifiable {
    case dashboard, processes, cpu, gpu, memory, disk, network
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .processes: return "Processes"
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "Memory"
        case .disk: return "Disk"
        case .network: return "Network"
        }
    }

    var sidebarLabel: String {
        switch self {
        case .processes: return "Top Processes"
        case .disk: return "Disk I/O"
        default: return title
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .processes: return "list.bullet.rectangle.portrait"
        case .cpu: return "cpu"
        case .gpu: return "display"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        case .network: return "network"
        }
    }
}

// MARK: - Main window

struct ContentView: View {
    @Environment(MonitorViewModel.self) private var vm
    /// Persisted so the app reopens where you left it.
    @AppStorage("selectedTab") private var selectedTabRaw = Tab.dashboard.rawValue
    @State private var isWindowVisible = true
    @AppStorage(HUD.visibilityKey) private var showHUD = false
    @Environment(\.openWindow) private var openWindow
    @Namespace private var glassNS

    private var selectedTab: Tab { Tab(rawValue: selectedTabRaw) ?? .dashboard }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            ScrollView {
                // One container batches every glass card into a single render pass.
                // Its spacing is the distance at which shapes *merge*: 0 keeps cards distinct.
                GlassEffectContainer(spacing: 0) {
                    detail
                        .glassEffectID(selectedTab.rawValue, in: glassNS)
                        .padding(24)
                        .frame(maxWidth: 1100)
                        .frame(maxWidth: .infinity)
                }
            }
            .background(VisualEffectView(material: .windowBackground, blendingMode: .behindWindow).ignoresSafeArea())
            .navigationTitle(selectedTab.title)
            .navigationSubtitle(selectedTab == .dashboard ? "" : vm.status.text)
        }
        .frame(minWidth: 900, minHeight: 650)
        // Nothing here is worth updating while the window can't be seen: the view model
        // stops publishing dashboard values, and process sampling (the one expensive
        // monitor) runs only while its tab is actually on screen.
        .background(WindowVisibilityReader { isWindowVisible = $0 })
        .onChange(of: isWindowVisible, initial: true) { _, visible in
            vm.setVisible(.dashboard, visible)
        }
        .onChange(of: selectedTab == .processes && isWindowVisible, initial: true) { _, active in
            vm.processMonitor.setActive(active)
        }
        .onAppear {
            // Restore the HUD if it was on when the app last quit. SwiftUI won't present a
            // secondary window at launch on its own, and openWindow on a `Window` scene is
            // idempotent, so this can never create a duplicate.
            if showHUD { openWindow(id: SceneID.hud) }
        }
        .onDisappear {
            vm.setVisible(.dashboard, false)
            vm.processMonitor.setActive(false)
        }
        #if DEBUG
        .preferredColorScheme(DebugOverrides.colorScheme)
        #endif
    }

    private var sidebar: some View {
        List(selection: Binding<Tab?>(
            get: { selectedTab },
            set: { tab in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    selectedTabRaw = (tab ?? .dashboard).rawValue
                }
            }
        )) {
            Section("Overview") {
                row(.dashboard)
                row(.processes)
            }
            Section("Hardware") {
                row(.cpu) { SidebarBadge(text: "\(vm.cpuPercent)%", tint: Theme.loadColor(Double(vm.cpuPercent))) }
                row(.gpu) { SidebarBadge(text: "\(vm.gpuPercent)%", tint: Theme.amethyst) }
                row(.memory) { SidebarBadge(text: "\(vm.memPercent)%", tint: Theme.color(for: vm.memoryPressure)) }
                row(.disk)
                row(.network)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
    }

    private func row<Badge: View>(_ tab: Tab, @ViewBuilder badge: () -> Badge = { EmptyView() }) -> some View {
        NavigationLink(value: tab) {
            HStack {
                Label(tab.sidebarLabel, systemImage: tab.icon)
                Spacer()
                badge()
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch selectedTab {
        case .dashboard: DashboardView()
        case .processes: ProcessesView(monitor: vm.processMonitor)
        case .cpu: CPUView()
        case .gpu: GPUView()
        case .memory: MemoryView()
        case .disk: DiskView()
        case .network: NetworkView()
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @Environment(MonitorViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.status.text)
                        .font(.headline)
                        .foregroundStyle(Theme.color(for: vm.status.level))
                    Text("Up \(vm.uptime)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(icon: "thermometer.medium",
                           text: "Thermal: \(Format.thermal(vm.thermalState))",
                           color: Theme.color(for: vm.thermalState))
                HUDToggleButton()
            }
            .glassCard(alignment: .leading)

            Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                GridRow {
                    VStack(alignment: .leading, spacing: 10) {
                        CardHeader(icon: "cpu", title: "CPU", tint: Theme.loadColor(vm.cpu)) {
                            Text(Format.percent(vm.cpu)).metricFont(.title3).foregroundStyle(Theme.loadColor(vm.cpu))
                        }
                        Sparkline(vm.cpuHistory, color: Theme.loadColor(vm.cpu), maxValue: 100).frame(height: 56)
                    }
                    .glassCard()

                    VStack(alignment: .leading, spacing: 10) {
                        CardHeader(icon: "display", title: "GPU", tint: Theme.amethyst) {
                            Text(Format.percent(vm.gpu)).metricFont(.title3).foregroundStyle(Theme.amethyst)
                        }
                        Sparkline(vm.gpuHistory, color: Theme.amethyst, maxValue: 100).frame(height: 56)
                    }
                    .glassCard()
                }
                GridRow {
                    VStack(alignment: .leading, spacing: 10) {
                        CardHeader(icon: "memorychip", title: "Memory", tint: Theme.color(for: vm.memoryPressure)) {
                            PressureLabel(pressure: vm.memoryPressure)
                        }
                        HStack {
                            GlassRingGauge(value: Double(vm.memPercent), color: Theme.color(for: vm.memoryPressure),
                                           label: "Used", accessibilityName: "Memory used")
                            Spacer()
                            if let m = vm.memorySummary {
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("\(Format.gigabytes(m.usedGB)) used").foregroundStyle(.secondary)
                                    Text("\(Format.gigabytes(m.freeGB)) free").foregroundStyle(.secondary)
                                    Text("\(Format.gigabytes(m.totalGB, decimals: 0)) total").bold()
                                }
                                .font(.caption.monospacedDigit())
                            }
                        }
                    }
                    .glassCard()

                    VStack(alignment: .leading, spacing: 12) {
                        CardHeader(icon: "network", title: "Network", tint: Theme.ocean)
                        ActivityGaugeRow(label: "Download", value: vm.netInText, fraction: vm.netInFraction, color: Theme.ocean)
                        ActivityGaugeRow(label: "Upload", value: vm.netOutText, fraction: vm.netOutFraction, color: Theme.rose)
                    }
                    .glassCard()
                }
            }
        }
    }
}

struct PressureLabel: View {
    let pressure: MemoryPressure

    var body: some View {
        Text("Pressure: \(pressure.label)")
            .font(.caption.bold())
            .foregroundStyle(Theme.color(for: pressure))
    }
}

/// Shows or hides the floating HUD, keeping the stored preference in sync.
struct HUDToggleButton: View {
    @AppStorage(HUD.visibilityKey) private var isVisible = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Button {
            HUD.setVisible(!isVisible, open: openWindow, dismiss: dismissWindow)
        } label: {
            Label(isVisible ? "Hide HUD" : "Show HUD", systemImage: isVisible ? "pip.exit" : "pip.enter")
                .font(.subheadline.bold())
                .foregroundStyle(isVisible ? Theme.amethyst : .primary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(TactileButtonStyle())
        .help("A small always-on-top readout of CPU and memory")
    }
}

// MARK: - Processes

struct ProcessesView: View {
    @Bindable var monitor: ProcessMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Top Processes").font(.headline)
                Text("The \(ProcessMonitor.rowLimit) busiest processes running under your account, refreshed every 2 seconds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !monitor.hasMeasured {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Measuring…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                header
                Divider()
                LazyVStack(spacing: 0) {
                    ForEach(Array(monitor.topProcesses.enumerated()), id: \.element.id) { index, process in
                        ProcessRow(process: process)
                            .background(index.isMultiple(of: 2) ? Color.primary.opacity(0.035) : .clear, in: .rect(cornerRadius: 6))
                    }
                }
            }

            Text("System processes owned by other users (such as WindowServer and kernel_task) aren’t visible to sandboxed apps.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .glassCard()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Name").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 26)
            Text("PID").frame(width: ProcessRow.pidWidth, alignment: .trailing)
            sortButton(.cpu, title: "% CPU", width: ProcessRow.cpuWidth)
            sortButton(.memory, title: "Real Mem", width: ProcessRow.memWidth)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
    }

    /// Click a column heading to sort by it, as in Finder or Activity Monitor.
    private func sortButton(_ key: ProcessSortKey, title: String, width: CGFloat) -> some View {
        Button {
            monitor.sortKey = key
        } label: {
            HStack(spacing: 3) {
                Text(title)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(monitor.sortKey == key ? 1 : 0)
            }
            .fontWeight(monitor.sortKey == key ? .semibold : .regular)
            .foregroundStyle(monitor.sortKey == key ? .primary : .secondary)
            .frame(width: width, alignment: .trailing)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort by \(key.label)")
        .accessibilityAddTraits(monitor.sortKey == key ? .isSelected : [])
    }
}

struct ProcessRow: View {
    static let pidWidth: CGFloat = 56
    static let cpuWidth: CGFloat = 68
    static let memWidth: CGFloat = 84

    let process: ProcessEntry

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let icon = process.icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "gearshape").foregroundStyle(.tertiary)
                }
            }
            .frame(width: 18, height: 18)

            Text(process.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(process.pid)")
                .foregroundStyle(.secondary)
                .frame(width: Self.pidWidth, alignment: .trailing)
            Text(String(format: "%.1f", process.cpuPercent))
                .foregroundStyle(process.cpuPercent > 65 ? Theme.loadColor(process.cpuPercent) : .primary)
                .frame(width: Self.cpuWidth, alignment: .trailing)
            Text(Format.memory(process.memoryBytes))
                .frame(width: Self.memWidth, alignment: .trailing)
        }
        .font(.callout.monospacedDigit())
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(process.name)
        .accessibilityValue("\(String(format: "%.1f", process.cpuPercent)) percent CPU, \(Format.memory(process.memoryBytes)) memory")
    }
}

// MARK: - CPU

struct CPUView: View {
    @Environment(MonitorViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 16) {
            DetailHeader(title: SystemInfo.cpuModel.isEmpty ? "Processor" : SystemInfo.cpuModel,
                         subtitle: "\(vm.coreUsages.count) cores · average load",
                         value: Format.percent(vm.cpu),
                         color: Theme.loadColor(vm.cpu))

            VStack(alignment: .leading, spacing: 10) {
                CardHeader(icon: "waveform.path.ecg", title: "Load · last 30 seconds")
                Sparkline(vm.cpuHistory, color: Theme.loadColor(vm.cpu), maxValue: 100).frame(height: 100)
            }
            .glassCard()

            VStack(alignment: .leading, spacing: 12) {
                CardHeader(icon: "square.grid.3x3", title: "Cores")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 10)], spacing: 10) {
                    ForEach(Array(vm.coreUsages.enumerated()), id: \.offset) { index, usage in
                        CoreTile(index: index, usage: usage)
                    }
                }
            }
            .glassCard()
        }
    }
}

struct CoreTile: View {
    let index: Int
    let usage: Double

    var body: some View {
        let color = Theme.loadColor(usage)
        VStack(alignment: .leading, spacing: 6) {
            Text("Core \(index + 1)").font(.caption).foregroundStyle(.secondary)
            Text(Format.percent(usage)).metricFont(.title3).foregroundStyle(color)
            // Bar snaps to 2% steps (~2 px): finer changes are invisible but would still animate.
            FillBar(fraction: Theme.quantize(usage, step: 2) / 100, color: color)
        }
        .padding(10)
        .background(color.opacity(0.05 + usage / 100 * 0.1), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.06)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Core \(index + 1)")
        .accessibilityValue("\(Int(usage.rounded())) percent")
    }
}

// MARK: - GPU

struct GPUView: View {
    @Environment(MonitorViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 16) {
            DetailHeader(title: SystemInfo.gpuModel.isEmpty ? "Graphics Processor" : SystemInfo.gpuModel,
                         subtitle: "Device utilization",
                         value: Format.percent(vm.gpu),
                         color: Theme.amethyst)

            VStack(alignment: .leading, spacing: 10) {
                CardHeader(icon: "waveform.path.ecg", title: "Utilization · last 30 seconds")
                Sparkline(vm.gpuHistory, color: Theme.amethyst, maxValue: 100).frame(height: 120)
                Text("How busy the GPU is across all apps, including the system compositing your windows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .glassCard()
        }
    }
}

// MARK: - Memory

struct MemoryView: View {
    @Environment(MonitorViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 16) {
            if let m = vm.memoryInfo {
                HStack(alignment: .center, spacing: 32) {
                    GlassRingGauge(value: Double(vm.memPercent), color: Theme.color(for: m.pressure),
                                   label: "Used", accessibilityName: "Memory used")
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Memory").font(.headline)
                            Spacer()
                            PressureLabel(pressure: m.pressure)
                        }
                        breakdownRow("Active", m.activeGB, Theme.amber)
                        breakdownRow("Wired", m.wiredGB, Theme.terracotta)
                        breakdownRow("Compressed", m.compressedGB, Theme.ocean)
                        breakdownRow("Free & Cached", m.freeGB, Theme.sage)
                        Divider().padding(.vertical, 2)
                        breakdownRow("Swap Used", m.swapUsedGB, nil)
                        breakdownRow("Installed", m.totalGB, nil)
                    }
                }
                .glassCard(alignment: .leading)

                Text("High memory use is normal: macOS keeps RAM full of cached data to make your Mac faster. **Pressure** is what matters — it turns amber or red only when macOS struggles to make room for apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func breakdownRow(_ label: String, _ gb: Double, _ color: Color?) -> some View {
        HStack {
            Circle().fill(color ?? .clear).frame(width: 8, height: 8)
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(Format.gigabytes(gb, decimals: 2)).font(.system(.subheadline, design: .rounded).monospacedDigit().bold())
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Disk

struct DiskView: View {
    @Environment(MonitorViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 16) {
            if let d = vm.diskSpace {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(d.volumeName).font(.headline)
                        Spacer()
                        Text("\(Format.storage(d.availableBytes)) available")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    FillBar(fraction: d.usedFraction, color: Theme.terracotta, height: 10)
                    HStack {
                        Text("\(Format.storage(d.usedBytes)) used").foregroundStyle(Theme.terracotta)
                        Spacer()
                        Text("\(Format.storage(d.totalBytes)) total").bold()
                    }
                    .font(.caption.monospacedDigit())
                }
                .glassCard()
                .accessibilityElement(children: .combine)
            }

            VStack(alignment: .leading, spacing: 12) {
                CardHeader(icon: "internaldrive", title: "Throughput", tint: Theme.terracotta)
                ActivityGaugeRow(label: "Read", value: vm.diskReadText, fraction: vm.diskReadFraction, color: Theme.terracotta)
                ActivityGaugeRow(label: "Write", value: vm.diskWriteText, fraction: vm.diskWriteFraction, color: Theme.amber)
            }
            .glassCard()

            HistoryCard(inData: vm.diskReadHistory, inLabel: "Read", inColor: Theme.terracotta,
                        outData: vm.diskWriteHistory, outLabel: "Write", outColor: Theme.amber,
                        minimumScale: MonitorViewModel.diskScaleFloor)
        }
    }
}

// MARK: - Network

struct NetworkView: View {
    @Environment(MonitorViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(icon: "network", title: "Activity", tint: Theme.ocean)
                ActivityGaugeRow(label: "Download", value: vm.netInText, fraction: vm.netInFraction, color: Theme.ocean)
                ActivityGaugeRow(label: "Upload", value: vm.netOutText, fraction: vm.netOutFraction, color: Theme.rose)
            }
            .glassCard()

            HistoryCard(inData: vm.netInHistory, inLabel: "Download", inColor: Theme.ocean,
                        outData: vm.netOutHistory, outLabel: "Upload", outColor: Theme.rose,
                        minimumScale: MonitorViewModel.networkScaleFloor)
        }
    }
}

/// Two throughput series on one shared, auto-scaling graph.
struct HistoryCard: View {
    let inData: [ChartDataPoint]
    let inLabel: String
    let inColor: Color
    let outData: [ChartDataPoint]
    let outLabel: String
    let outColor: Color
    var minimumScale: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(icon: "waveform.path.ecg", title: "History · last 30 seconds") {
                HStack(spacing: 12) {
                    LegendItem(color: inColor, label: inLabel)
                    LegendItem(color: outColor, label: outLabel)
                }
            }
            Sparkline(series: [.init(data: inData, color: inColor), .init(data: outData, color: outColor)],
                      minimumScale: minimumScale)
                .frame(height: 100)
        }
        .glassCard()
    }
}

// MARK: - Shared detail header

/// The first card on a hardware tab. The tab name is already in the toolbar, so this
/// leads with what the hardware is, next to its headline number.
struct DetailHeader: View {
    let title: String
    let subtitle: String
    let value: String
    let color: Color

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.bold())
                if !subtitle.isEmpty {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(value).metricFont(.largeTitle).foregroundStyle(color)
        }
        .glassCard(alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
/// Debug-only launch overrides, e.g. `-RTColorScheme dark`, for screenshots in either
/// appearance without changing the system setting.
enum DebugOverrides {
    static var colorScheme: ColorScheme? {
        switch UserDefaults.standard.string(forKey: "RTColorScheme") {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }
}
#endif

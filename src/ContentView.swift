import SwiftUI
import Charts
import AppKit

// MARK: - Color Palette
struct Theme {
    static let sage = Color(red: 0.38, green: 0.49, blue: 0.43)
    static let amber = Color(red: 0.82, green: 0.61, blue: 0.33)
    static let terracotta = Color(red: 0.76, green: 0.44, blue: 0.32)
    static let ocean = Color(red: 0.34, green: 0.47, blue: 0.54)
    static let amethyst = Color(red: 0.58, green: 0.44, blue: 0.86)

    static func statusColor(pressure: Double) -> Color {
        if pressure > 85 { return .red }
        if pressure > 65 { return amber }
        return sage
    }
}

// MARK: - Glass Style Modifier
extension View {
    func glassCardStyle() -> some View {
        self
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}

// MARK: - Tactile Spring Button Style
struct TactileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Data Models
struct ChartDataPoint: Identifiable {
    let id = UUID()
    let time: Date
    let value: Double
}

// MARK: - View Model
class MonitorViewModel: ObservableObject {
    private let cpuMonitor = CPUMonitor()
    private let memMonitor = MemoryMonitor()
    private let netMonitor = NetworkMonitor()
    private let diskMonitor = DiskMonitor()
    private let gpuMonitor = GPUMonitor()
    public let processMonitor = ProcessMonitor()

    private var timer: Timer?

    // Boot time is constant for the life of the process — read it once.
    private let bootDate: Date = MonitorViewModel.systemBootDate()

    @Published var cpuCoreUsages: [Double] = []
    @Published var overallCpu: Double = 0.0
    @Published var memoryInfo: MemoryMonitor.MemoryInfo? = nil
    @Published var gpuUtilization: Double = 0.0

    @Published var displayCpu: Double = 0.0
    @Published var displayGpu: Double = 0.0
    @Published var displayMemUsage: Double = 0.0
    @Published var displayNetInRate: Double = 0.0
    @Published var displayNetOutRate: Double = 0.0
    @Published var displayDiskReadRate: Double = 0.0
    @Published var displayDiskWriteRate: Double = 0.0
    @Published var displayCpuCoreUsages: [Double] = []
    @Published var diskSpace: (totalGB: Double, freeGB: Double, usedGB: Double)? = nil
    @Published var displayThermalState: Foundation.ProcessInfo.ThermalState = .nominal

    @Published var uptimeString: String = ""
    @Published var systemStatusText: String = "Cruising smoothly."

    @Published var cpuHistory: [ChartDataPoint] = []
    @Published var gpuHistory: [ChartDataPoint] = []
    @Published var netDownloadHistory: [ChartDataPoint] = []
    @Published var diskReadHistory: [ChartDataPoint] = []

    init() {
        let now = Date()
        for i in 0..<30 {
            let pt = ChartDataPoint(time: now.addingTimeInterval(Double(i - 30)), value: 0.0)
            cpuHistory.append(pt); gpuHistory.append(pt)
            netDownloadHistory.append(pt); diskReadHistory.append(pt)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.updateStats() }
        updateStats()
    }

    deinit {
        timer?.invalidate()
        processMonitor.stop()
    }

    /// Kernel boot time via sysctl. Read once; it does not change while running.
    private static func systemBootDate() -> Date {
        var mib = [CTL_KERN, KERN_BOOTTIME]
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.stride
        if sysctl(&mib, 2, &bootTime, &size, nil, 0) == 0, bootTime.tv_sec != 0 {
            return Date(timeIntervalSince1970: Double(bootTime.tv_sec))
        }
        return Date()
    }

    private func updateStats() {
        let now = Date()
        let cores = self.cpuMonitor.getCPUUsages()
        let avgCpu = cores.isEmpty ? 0.0 : cores.reduce(0.0, +) / Double(cores.count)
        let mem = self.memMonitor.getMemoryInfo()
        let (inRate, outRate) = self.netMonitor.getNetworkRates()
        let (readRate, writeRate) = self.diskMonitor.getDiskRates()
        let diskInfo = self.diskMonitor.getDiskSpaceInfo()
        let gpu = self.gpuMonitor.getGPUUtilization()
        let thermal = Foundation.ProcessInfo.processInfo.thermalState

        let uptimeSec = max(0, now.timeIntervalSince(bootDate))
        let days = Int(uptimeSec) / 86400
        let hours = (Int(uptimeSec) % 86400) / 3600
        let mins = (Int(uptimeSec) % 3600) / 60

        let memUsage = mem?.usedPercentage ?? 0.0

        var status = "Cruising smoothly."
        if thermal == .critical {
            status = "CRITICAL: Your Mac is dangerously hot and heavily throttling."
        } else if thermal == .serious {
            status = "WARNING: Your Mac is overheating and slowing down to cool off."
        } else if memUsage > 85 || avgCpu > 85 {
            status = "Your Mac is breaking a sweat. Consider closing some heavy apps."
        } else if memUsage > 65 || avgCpu > 65 {
            status = "Working hard right now."
        }

        self.cpuCoreUsages = cores
        self.overallCpu = avgCpu
        self.memoryInfo = mem
        self.gpuUtilization = gpu

        self.cpuHistory.removeFirst(); self.cpuHistory.append(ChartDataPoint(time: now, value: avgCpu))
        self.gpuHistory.removeFirst(); self.gpuHistory.append(ChartDataPoint(time: now, value: gpu))
        self.netDownloadHistory.removeFirst(); self.netDownloadHistory.append(ChartDataPoint(time: now, value: inRate))
        self.diskReadHistory.removeFirst(); self.diskReadHistory.append(ChartDataPoint(time: now, value: readRate))

        self.displayCpuCoreUsages = cores
        self.displayCpu = avgCpu
        self.displayGpu = gpu
        self.displayMemUsage = memUsage
        self.displayNetInRate = inRate
        self.displayNetOutRate = outRate
        self.displayDiskReadRate = readRate
        self.displayDiskWriteRate = writeRate
        self.displayThermalState = thermal
        if let space = diskInfo { self.diskSpace = space }
        self.uptimeString = "\(days)d \(hours)h \(mins)m"
        self.systemStatusText = status
    }
}

// MARK: - Thin Sparkline (no heavy area fill)
struct ThinSparkline: View {
    var data: [ChartDataPoint]
    var color: Color
    var maxVal: Double? = nil

    var body: some View {
        let yMax = maxVal ?? (data.map { $0.value }.max() ?? 1.0)
        let limit = yMax <= 0 ? 1.0 : yMax
        Chart(data) { point in
            LineMark(
                x: .value("Time", point.time),
                y: .value("Value", point.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                LinearGradient(
                    colors: [color, color.opacity(0.5)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...limit)
    }
}

// MARK: - Glass Ring Gauge
struct GlassRingGauge: View {
    let value: Double
    let color: Color
    let label: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 14)
            Circle()
                .trim(from: 0, to: CGFloat(min(value / 100.0, 1.0)))
                .stroke(
                    AngularGradient(colors: [color.opacity(0.7), color], center: .center),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.7, dampingFraction: 0.75), value: value)
            VStack(spacing: 2) {
                Text(String(format: "%.0f%%", value))
                    .font(.system(.title2, design: .rounded)).bold()
                    .foregroundColor(color)
                Text(label)
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .frame(width: 100, height: 100)
    }
}

// MARK: - Activity Gauge Row
struct ActivityGaugeRow: View {
    let label: String
    let value: String
    let subtitle: String
    let fraction: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.caption).foregroundColor(.secondary)
                Spacer()
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption2).foregroundColor(.secondary)
                }
            }
            Text(value)
                .font(.system(.title3, design: .rounded)).bold()
                .foregroundColor(color)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [color.opacity(0.6), color], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(geo.size.width * CGFloat(min(fraction, 1.0)), 4))
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: fraction)
                }
            }
            .frame(height: 5)
        }
    }
}

// MARK: - Dynamic Status Pill
struct StatusPill: View {
    let text: String
    let color: Color
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption)
            Text(text).font(.caption).bold()
        }
        .foregroundColor(color)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: text)
    }
}

// MARK: - NSImage bridge
struct NSImageViewRepresentable: NSViewRepresentable {
    let image: NSImage
    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView(); v.imageScaling = .scaleProportionallyUpOrDown; return v
    }
    func updateNSView(_ nsView: NSImageView, context: Context) { nsView.image = image }
}

// MARK: - Stat Card
struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.subheadline).foregroundColor(.secondary)
            Text(value).font(.title2).bold().foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .glassCardStyle()
    }
}

// MARK: - Navigation Tabs
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
        case .network: return "wifi"
        }
    }
}

// MARK: - Main Content View
public struct ContentView: View {
    @EnvironmentObject var vm: MonitorViewModel
    @State private var selectedTab: Tab? = .dashboard
    @AppStorage("showMiniHUD") private var showMiniHUD: Bool = false
    @Environment(\.openWindow) private var openWindow
    @Namespace private var glassNS

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(selection: Binding(
                get: { self.selectedTab },
                set: { newValue in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        self.selectedTab = newValue
                    }
                    vm.processMonitor.setGhostMode(newValue != .processes)
                }
            )) {
                Section(header: Text("Overview").foregroundColor(.secondary)) {
                    NavigationLink(value: Tab.dashboard) { Label(Tab.dashboard.sidebarLabel, systemImage: Tab.dashboard.icon) }
                    NavigationLink(value: Tab.processes) { Label(Tab.processes.sidebarLabel, systemImage: Tab.processes.icon) }
                }
                Section(header: Text("Hardware").foregroundColor(.secondary)) {
                    NavigationLink(value: Tab.cpu) {
                        HStack {
                            Label(Tab.cpu.sidebarLabel, systemImage: Tab.cpu.icon); Spacer()
                            Text(String(format: "%.0f%%", vm.displayCpu)).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2).background(Theme.statusColor(pressure: vm.displayCpu).opacity(0.2)).cornerRadius(8)
                        }
                    }
                    NavigationLink(value: Tab.gpu) {
                        HStack {
                            Label(Tab.gpu.sidebarLabel, systemImage: Tab.gpu.icon); Spacer()
                            Text(String(format: "%.0f%%", vm.displayGpu)).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2).background(Theme.amethyst.opacity(0.2)).cornerRadius(8)
                        }
                    }
                    NavigationLink(value: Tab.memory) {
                        HStack {
                            Label(Tab.memory.sidebarLabel, systemImage: Tab.memory.icon); Spacer()
                            Text(String(format: "%.0f%%", vm.displayMemUsage)).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2).background(Theme.statusColor(pressure: vm.displayMemUsage).opacity(0.2)).cornerRadius(8)
                        }
                    }
                    NavigationLink(value: Tab.disk) { Label(Tab.disk.sidebarLabel, systemImage: Tab.disk.icon) }
                    NavigationLink(value: Tab.network) { Label(Tab.network.sidebarLabel, systemImage: Tab.network.icon) }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 250)

        } detail: {
            ScrollView {
                VStack(spacing: 20) {
                    switch selectedTab ?? .dashboard {
                    case .dashboard: dashboardView.glassEffectID(Tab.dashboard.rawValue, in: glassNS)
                    case .processes: processesView.glassEffectID(Tab.processes.rawValue, in: glassNS)
                    case .cpu: cpuDetailsView.glassEffectID(Tab.cpu.rawValue, in: glassNS)
                    case .gpu: gpuDetailsView.glassEffectID(Tab.gpu.rawValue, in: glassNS)
                    case .memory: memoryDetailsView.glassEffectID(Tab.memory.rawValue, in: glassNS)
                    case .disk: diskDetailsView.glassEffectID(Tab.disk.rawValue, in: glassNS)
                    case .network: networkDetailsView.glassEffectID(Tab.network.rawValue, in: glassNS)
                    }
                }.padding(24)
            }
            .background(VisualEffectView(material: .windowBackground, blendingMode: .behindWindow).ignoresSafeArea())
            .navigationTitle(selectedTab?.title ?? "Resource Tracker")
            .navigationSubtitle(Text(vm.systemStatusText))
        }
        .frame(minWidth: 900, minHeight: 650)
        .background(WindowAccessor { window in
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
        })
        .onAppear {
            if showMiniHUD {
                openWindow(id: "hud")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApp.windows.first { $0.level == .floating && $0.styleMask.contains(.borderless) }?.makeKeyAndOrderFront(nil)
                }
            }
        }
    }

    // MARK: - Dashboard View
    private var dashboardView: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.systemStatusText).font(.headline).foregroundColor(Theme.statusColor(pressure: vm.displayCpu))
                    Text("System Uptime: \(vm.uptimeString)").font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
                StatusPill(text: thermalString(state: vm.displayThermalState), color: thermalColor(state: vm.displayThermalState), icon: "thermometer.sun.fill")
                Spacer().frame(width: 10)
                Button(action: {
                    showMiniHUD.toggle()
                    if showMiniHUD {
                        openWindow(id: "hud")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            NSApp.windows.first { $0.level == .floating && $0.styleMask.contains(.borderless) }?.makeKeyAndOrderFront(nil)
                        }
                    } else {
                        NSApp.windows.forEach { if $0.level == .floating && $0.styleMask.contains(.borderless) { $0.close() } }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: showMiniHUD ? "macwindow.badge.minus" : "macwindow.badge.plus")
                        Text(showMiniHUD ? "Hide HUD" : "Show HUD")
                    }
                    .font(.subheadline).bold()
                    .foregroundColor(showMiniHUD ? Theme.amethyst : .primary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
                }
                .buttonStyle(TactileButtonStyle())
            }
            .glassCardStyle()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "cpu").foregroundColor(Theme.statusColor(pressure: vm.displayCpu))
                        Text("CPU LOAD").font(.system(.caption, design: .rounded)).bold().foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1f%%", vm.displayCpu)).font(.system(.title3, design: .rounded)).bold().foregroundColor(Theme.statusColor(pressure: vm.displayCpu))
                    }
                    ThinSparkline(data: vm.cpuHistory, color: Theme.statusColor(pressure: vm.overallCpu), maxVal: 100.0).frame(height: 50)
                }.glassCardStyle()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "display").foregroundColor(Theme.amethyst)
                        Text("GPU").font(.system(.caption, design: .rounded)).bold().foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1f%%", vm.displayGpu)).font(.system(.title3, design: .rounded)).bold().foregroundColor(Theme.amethyst)
                    }
                    ThinSparkline(data: vm.gpuHistory, color: Theme.amethyst, maxVal: 100.0).frame(height: 50)
                }.glassCardStyle()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "memorychip").foregroundColor(Theme.statusColor(pressure: vm.displayMemUsage))
                        Text("MEMORY").font(.system(.caption, design: .rounded)).bold().foregroundColor(.secondary)
                        Spacer()
                    }
                    HStack {
                        GlassRingGauge(value: vm.displayMemUsage, color: Theme.statusColor(pressure: vm.displayMemUsage), label: "Used")
                        Spacer()
                        if let m = vm.memoryInfo {
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(String(format: "%.1f GB active", m.activeGB)).font(.caption).foregroundColor(.secondary)
                                Text(String(format: "%.1f GB free", m.freeGB)).font(.caption).foregroundColor(Theme.sage)
                                Text(String(format: "%.1f GB total", m.totalGB)).font(.caption).bold()
                            }
                        }
                    }
                }.glassCardStyle()

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "wifi").foregroundColor(Theme.ocean)
                        Text("NETWORK").font(.system(.caption, design: .rounded)).bold().foregroundColor(.secondary)
                        Spacer()
                    }
                    let maxNet = max(vm.displayNetInRate, vm.displayNetOutRate, 1.0)
                    ActivityGaugeRow(label: "Download", value: formatBytes(vm.displayNetInRate) + "/s", subtitle: "", fraction: vm.displayNetInRate / maxNet, color: Theme.ocean)
                    ActivityGaugeRow(label: "Upload", value: formatBytes(vm.displayNetOutRate) + "/s", subtitle: "", fraction: vm.displayNetOutRate / maxNet, color: Theme.ocean.opacity(0.6))
                }.glassCardStyle()
            }
        }
    }

    // MARK: - Processes View
    private var processesView: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Top Processes (Auto-sorted by CPU usage)").font(.headline).foregroundColor(.secondary)
            if vm.processMonitor.topProcesses.isEmpty {
                Text("Hunting for heavy processes...").foregroundColor(.secondary).padding()
            } else {
                VStack(spacing: 8) {
                    HStack {
                        Text("App").frame(width: 32, alignment: .leading).foregroundColor(.secondary)
                        Text("Process Name").frame(maxWidth: .infinity, alignment: .leading).foregroundColor(.secondary)
                        Text("PID").frame(width: 50, alignment: .leading).foregroundColor(.secondary)
                        Text("CPU").frame(width: 60, alignment: .trailing).foregroundColor(.secondary)
                        Text("Memory").frame(width: 80, alignment: .trailing).foregroundColor(.secondary)
                    }.font(.caption).padding(.horizontal)
                    Divider()
                    ForEach(vm.processMonitor.topProcesses) { process in
                        HStack {
                            if let icon = process.icon { NSImageViewRepresentable(image: icon).frame(width: 24, height: 24) }
                            else { Image(systemName: "apple.terminal").frame(width: 24, height: 24).foregroundColor(.secondary) }
                            Text(process.name).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                            Text("\(process.pid)").frame(width: 50, alignment: .leading).font(.caption.monospacedDigit()).foregroundColor(.secondary)
                            Text(String(format: "%.1f%%", process.cpuPercent)).frame(width: 60, alignment: .trailing).font(.caption.monospacedDigit()).foregroundColor(process.cpuPercent > 50.0 ? .red : .primary)
                            Text(formatBytes(Double(process.memoryBytes))).frame(width: 80, alignment: .trailing).font(.caption.monospacedDigit())
                        }
                        .padding(.vertical, 4).padding(.horizontal)
                        .background(Color.primary.opacity(0.02)).cornerRadius(6)
                    }
                }
            }
        }.glassCardStyle()
    }

    // MARK: - CPU Details View
    private var cpuDetailsView: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Overall CPU Load").font(.headline)
                    Text("Total process scheduling overhead").font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
                Text(String(format: "%.1f%%", vm.displayCpu)).font(.system(.largeTitle, design: .rounded)).bold().foregroundColor(Theme.statusColor(pressure: vm.displayCpu))
            }.glassCardStyle()

            VStack(alignment: .leading, spacing: 8) {
                Text("Live Load").font(.system(.caption, design: .rounded)).bold().foregroundColor(.secondary)
                ThinSparkline(data: vm.cpuHistory, color: Theme.statusColor(pressure: vm.overallCpu), maxVal: 100.0).frame(height: 80)
            }.glassCardStyle()

            VStack(alignment: .leading, spacing: 12) {
                Text("Processor Cores Activity").font(.system(.subheadline, design: .rounded)).bold().foregroundColor(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 12) {
                    ForEach(0..<vm.displayCpuCoreUsages.count, id: \.self) { idx in
                        let usage = vm.displayCpuCoreUsages[idx]
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Core \(idx)").font(.caption).foregroundColor(.secondary)
                            Text(String(format: "%.1f%%", usage)).font(.system(.title3, design: .rounded)).bold().foregroundColor(Theme.statusColor(pressure: usage))
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.08))
                                    Capsule().fill(Theme.statusColor(pressure: usage)).frame(width: geometry.size.width * CGFloat(usage / 100.0)).animation(.spring(response: 0.6, dampingFraction: 0.7), value: usage)
                                }
                            }.frame(height: 5)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.statusColor(pressure: usage).opacity(0.04 + (usage / 100.0) * 0.1)))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.05), lineWidth: 1))
                    }
                }
            }.glassCardStyle()
        }
    }

    // MARK: - GPU Details View
    private var gpuDetailsView: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Apple Silicon GPU Utilization").font(.headline)
                    Text("Hardware accelerator performance statistics").font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
                Text(String(format: "%.1f%%", vm.displayGpu)).font(.system(.largeTitle, design: .rounded)).bold().foregroundColor(Theme.amethyst)
            }.glassCardStyle()
            VStack(alignment: .leading, spacing: 8) {
                Text("Live Utilization").font(.system(.caption, design: .rounded)).bold().foregroundColor(.secondary)
                ThinSparkline(data: vm.gpuHistory, color: Theme.amethyst, maxVal: 100.0).frame(height: 120)
            }.glassCardStyle()
        }
    }

    // MARK: - Memory Details View
    private var memoryDetailsView: some View {
        VStack(spacing: 20) {
            if let m = vm.memoryInfo {
                HStack(spacing: 32) {
                    GlassRingGauge(value: vm.displayMemUsage, color: Theme.statusColor(pressure: vm.displayMemUsage), label: "Used")
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Memory Breakdown").font(.headline)
                        breakdownRow(label: "Active Memory", val: m.activeGB, color: Theme.amber)
                        breakdownRow(label: "Wired System", val: m.wiredGB, color: .orange)
                        breakdownRow(label: "Compressed", val: m.compressedGB, color: Theme.ocean)
                        breakdownRow(label: "Free / Cached", val: m.freeGB, color: Theme.sage)
                        Divider().padding(.vertical, 4)
                        HStack {
                            Text("Total Installed RAM").font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.1f GB", m.totalGB)).font(.subheadline).bold()
                        }
                    }
                }.glassCardStyle()
            }
        }
    }
    private func breakdownRow(label: String, val: Double, color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.subheadline).foregroundColor(.secondary)
            Spacer()
            Text(String(format: "%.2f GB", val)).font(.system(.subheadline, design: .rounded)).bold()
        }
    }

    // MARK: - Disk Details View
    private var diskDetailsView: some View {
        VStack(spacing: 20) {
            if let d = vm.diskSpace {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Macintosh HD Capacity").font(.headline)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule()
                                .fill(LinearGradient(colors: [Theme.terracotta.opacity(0.7), Theme.terracotta], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * CGFloat(d.usedGB / d.totalGB))
                                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: d.usedGB)
                        }
                    }.frame(height: 10)
                    HStack {
                        Text(String(format: "%.1f GB Used", d.usedGB)).font(.caption).foregroundColor(Theme.terracotta)
                        Spacer()
                        Text(String(format: "%.1f GB Free", d.freeGB)).font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1f GB Total", d.totalGB)).font(.caption).bold()
                    }
                }.glassCardStyle()
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("Disk Throughput").font(.system(.subheadline, design: .rounded)).bold().foregroundColor(.secondary)
                let maxDisk = max(vm.displayDiskReadRate, vm.displayDiskWriteRate, 1.0)
                ActivityGaugeRow(label: "Read", value: formatBytes(vm.displayDiskReadRate) + "/s", subtitle: "Active reads", fraction: vm.displayDiskReadRate / maxDisk, color: Theme.terracotta)
                ActivityGaugeRow(label: "Write", value: formatBytes(vm.displayDiskWriteRate) + "/s", subtitle: "Active writes", fraction: vm.displayDiskWriteRate / maxDisk, color: Theme.terracotta.opacity(0.6))
            }.glassCardStyle()
        }
    }

    // MARK: - Network Details View
    private var networkDetailsView: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Network Activity").font(.system(.subheadline, design: .rounded)).bold().foregroundColor(.secondary)
                let maxNet = max(vm.displayNetInRate, vm.displayNetOutRate, 1.0)
                ActivityGaugeRow(label: "Download", value: formatBytes(vm.displayNetInRate) + "/s", subtitle: "Inbound", fraction: vm.displayNetInRate / maxNet, color: Theme.ocean)
                ActivityGaugeRow(label: "Upload", value: formatBytes(vm.displayNetOutRate) + "/s", subtitle: "Outbound", fraction: vm.displayNetOutRate / maxNet, color: Theme.ocean.opacity(0.6))
            }.glassCardStyle()
            VStack(alignment: .leading, spacing: 8) {
                Text("Download History").font(.system(.caption, design: .rounded)).bold().foregroundColor(.secondary)
                ThinSparkline(data: vm.netDownloadHistory, color: Theme.ocean).frame(height: 80)
            }.glassCardStyle()
        }
    }

    // MARK: - Helpers
    private func formatBytes(_ bytes: Double) -> String {
        let kb = 1024.0; let mb = kb * 1024; let gb = mb * 1024
        if bytes >= gb { return String(format: "%.2f GB", bytes / gb) }
        if bytes >= mb { return String(format: "%.2f MB", bytes / mb) }
        if bytes >= kb { return String(format: "%.1f KB", bytes / kb) }
        return "\(Int(bytes)) B"
    }

    private func thermalColor(state: Foundation.ProcessInfo.ThermalState) -> Color {
        switch state {
        case .nominal: return Theme.sage
        case .fair: return Theme.amber
        case .serious: return .orange
        case .critical: return Theme.terracotta
        @unknown default: return .primary
        }
    }

    private func thermalString(state: Foundation.ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Nominal (Cool)"
        case .fair: return "Fair (Warm)"
        case .serious: return "Serious (Hot)"
        case .critical: return "Critical (Overheating)"
        @unknown default: return "Unknown"
        }
    }
}

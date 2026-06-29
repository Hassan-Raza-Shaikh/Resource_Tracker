import SwiftUI
import Charts
import AppKit

// MARK: - Color Palette
struct Theme {
    static let sage = Color(red: 0.38, green: 0.49, blue: 0.43)       // CPU
    static let amber = Color(red: 0.82, green: 0.61, blue: 0.33)      // Memory
    static let terracotta = Color(red: 0.76, green: 0.44, blue: 0.32) // Disk
    static let ocean = Color(red: 0.34, green: 0.47, blue: 0.54)       // Network
    static let amethyst = Color(red: 0.58, green: 0.44, blue: 0.86)    // GPU
    
    static func statusColor(pressure: Double) -> Color {
        if pressure > 85 { return .red }
        if pressure > 65 { return amber }
        return sage
    }
}

// MARK: - Glass Style Modifier
struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(LinearGradient(gradient: Gradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.02), Color.black.opacity(0.18), Color.white.opacity(0.06)]), startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}
extension View { func glassCardStyle() -> some View { self.modifier(GlassCard()) } }

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
    public let processMonitor = ProcessMonitor() // Public for ghost mode control
    
    private var timer: Timer?
    private var tickCount = 0

    // High Refresh Rate Data (For Charts & Gauges)
    @Published var cpuCoreUsages: [Double] = []
    @Published var overallCpu: Double = 0.0
    @Published var memoryInfo: MemoryMonitor.MemoryInfo? = nil
    @Published var gpuUtilization: Double = 0.0
    
    // Slow Refresh Rate Data (For Legible Text Numbers)
    @Published var displayCpu: Double = 0.0
    @Published var displayGpu: Double = 0.0
    @Published var displayMemPressure: Double = 0.0
    @Published var displayNetInRate: Double = 0.0
    @Published var displayNetOutRate: Double = 0.0
    @Published var displayDiskReadRate: Double = 0.0
    @Published var displayDiskWriteRate: Double = 0.0
    @Published var displayCpuCoreUsages: [Double] = []
    @Published var diskSpace: (totalGB: Double, freeGB: Double, usedGB: Double)? = nil
    @Published var displayThermalState: Foundation.ProcessInfo.ThermalState = .nominal
    
    @Published var uptimeString: String = ""
    @Published var systemStatusText: String = "Cruising smoothly."
    
    // Chart Histories
    @Published var cpuHistory: [ChartDataPoint] = []
    @Published var memHistory: [ChartDataPoint] = []
    @Published var gpuHistory: [ChartDataPoint] = []
    @Published var netDownloadHistory: [ChartDataPoint] = []
    @Published var diskReadHistory: [ChartDataPoint] = []

    init() {
        gpuMonitor.start()
        
        let now = Date()
        for i in 0..<30 {
            let pt = ChartDataPoint(time: now.addingTimeInterval(Double(i - 30)), value: 0.0)
            cpuHistory.append(pt); memHistory.append(pt); gpuHistory.append(pt); netDownloadHistory.append(pt); diskReadHistory.append(pt)
        }
        
        // Poll every 0.1 seconds for ultra-fast charts (10 FPS)
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.updateStats() }
        updateStats() // Fetch immediately to avoid empty arrays on startup
    }

    deinit {
        timer?.invalidate()
        gpuMonitor.stop()
        processMonitor.stop()
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
        
        tickCount += 1
        let shouldUpdateText = (tickCount % 10 == 1) // Update text every 1.0s (10 ticks * 0.1s)
        
        // Calculate Uptime
        var mib = [CTL_KERN, KERN_BOOTTIME]
        var size = MemoryLayout<timeval>.stride
        var bootTime = timeval()
        sysctl(&mib, 2, &bootTime, &size, nil, 0)
        let uptimeSec = Date().timeIntervalSince1970 - Double(bootTime.tv_sec)
        let days = Int(uptimeSec) / 86400
        let hours = (Int(uptimeSec) % 86400) / 3600
        let mins = (Int(uptimeSec) % 3600) / 60
        
        let memPress = mem?.pressurePercentage ?? 0.0
        
        // Friendly Status Logic
        var status = "Cruising smoothly."
        if thermal == .critical {
            status = "CRITICAL: Your Mac is dangerously hot and heavily throttling."
        } else if thermal == .serious {
            status = "WARNING: Your Mac is overheating and slowing down to cool off."
        } else if memPress > 85 || avgCpu > 85 {
            status = "Your Mac is breaking a sweat. Consider closing some heavy apps."
        } else if memPress > 65 || avgCpu > 65 {
            status = "Working hard right now."
        }
        
        // Update states directly without high-CPU withAnimation block
        self.cpuCoreUsages = cores
        self.overallCpu = avgCpu
        self.memoryInfo = mem
        self.gpuUtilization = gpu
        
        self.cpuHistory.removeFirst(); self.cpuHistory.append(ChartDataPoint(time: now, value: avgCpu))
        self.memHistory.removeFirst(); self.memHistory.append(ChartDataPoint(time: now, value: memPress))
        self.gpuHistory.removeFirst(); self.gpuHistory.append(ChartDataPoint(time: now, value: gpu))
        self.netDownloadHistory.removeFirst(); self.netDownloadHistory.append(ChartDataPoint(time: now, value: inRate))
        self.diskReadHistory.removeFirst(); self.diskReadHistory.append(ChartDataPoint(time: now, value: readRate))
        
        if shouldUpdateText {
            self.displayCpuCoreUsages = cores
            self.displayCpu = avgCpu
            self.displayGpu = gpu
            self.displayMemPressure = memPress
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
}

// (Removed Duplicate DashboardView struct)

// (Removed CoreStatsView)

// MARK: - Stat Card
struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2)
                .bold()
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .glassCardStyle()
    }
}
// MARK: - Smooth Live Chart
struct SmoothLiveChart: View {
    var data: [ChartDataPoint]
    var color: Color
    var maxVal: Double? = nil
    var body: some View {
        let yMax = maxVal ?? (data.map { $0.value }.max() ?? 1.0)
        let limit = yMax <= 0 ? 1.0 : yMax
        Chart(data) { point in
            LineMark(x: .value("Time", point.time), y: .value("Value", point.value)).interpolationMethod(.catmullRom).foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2))
            AreaMark(x: .value("Time", point.time), y: .value("Value", point.value)).interpolationMethod(.catmullRom).foregroundStyle(LinearGradient(gradient: Gradient(colors: [color.opacity(0.3), color.opacity(0.0)]), startPoint: .top, endPoint: .bottom))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...limit)
        .animation(.linear(duration: 0.1), value: data.map { $0.value })
    }
}

// MARK: - NSImage to SwiftUI Image Bridge
struct NSImageViewRepresentable: NSViewRepresentable {
    let image: NSImage
    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        return imageView
    }
    func updateNSView(_ nsView: NSImageView, context: Context) { nsView.image = image }
}

// MARK: - Main Content View
public struct ContentView: View {
    @EnvironmentObject var vm: MonitorViewModel
    @State private var selectedTab: String? = "Dashboard"
    @AppStorage("showMiniHUD") private var showMiniHUD: Bool = false
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(selection: Binding(
                get: { self.selectedTab },
                set: { newValue in
                    self.selectedTab = newValue
                    // Ghost Mode: Only run ProcessMonitor if viewing the Processes tab!
                    vm.processMonitor.setGhostMode(newValue != "Processes")
                }
            )) {
                Section(header: Text("Overview").foregroundColor(.secondary)) {
                    NavigationLink(value: "Dashboard") { Label("Dashboard", systemImage: "square.grid.2x2") }
                    NavigationLink(value: "Processes") { Label("Top Processes", systemImage: "list.bullet.rectangle.portrait") }
                }
                
                Section(header: Text("Hardware").foregroundColor(.secondary)) {
                    NavigationLink(value: "CPU") { HStack { Label("CPU", systemImage: "cpu"); Spacer(); Text(String(format: "%.0f%%", vm.displayCpu)).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2).background(Theme.statusColor(pressure: vm.displayCpu).opacity(0.2)).cornerRadius(8) } }
                    NavigationLink(value: "GPU") { HStack { Label("GPU", systemImage: "display"); Spacer(); Text(String(format: "%.0f%%", vm.displayGpu)).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2).background(Theme.amethyst.opacity(0.2)).cornerRadius(8) } }
                    NavigationLink(value: "Memory") { HStack { Label("Memory", systemImage: "memorychip"); Spacer(); Text(String(format: "%.0f%%", vm.displayMemPressure)).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2).background(Theme.statusColor(pressure: vm.displayMemPressure).opacity(0.2)).cornerRadius(8) } }
                    NavigationLink(value: "Disk") { Label("Disk I/O", systemImage: "internaldrive") }
                    NavigationLink(value: "Network") { Label("Network", systemImage: "wifi") }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 250)
            
        } detail: {
            ScrollView {
                VStack(spacing: 20) {
                    if selectedTab == "Dashboard" { dashboardView }
                    else if selectedTab == "Processes" { processesView }
                    else if selectedTab == "CPU" { cpuDetailsView }
                    else if selectedTab == "GPU" { gpuDetailsView }
                    else if selectedTab == "Memory" { memoryDetailsView }
                    else if selectedTab == "Disk" { diskDetailsView }
                    else if selectedTab == "Network" { networkDetailsView }
                }.padding(24)
            }
            .background(VisualEffectView(material: .windowBackground, blendingMode: .behindWindow).ignoresSafeArea())
            .navigationTitle(selectedTab ?? "Resource Tracker")
            .navigationSubtitle(Text(vm.systemStatusText))
        }
        .frame(minWidth: 900, minHeight: 650)
        .background(WindowAccessor { window in window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true; window.styleMask.insert(.fullSizeContentView); window.isMovableByWindowBackground = true })
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
            // Status Bar with Thermal State and HUD controls integrated
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.systemStatusText)
                        .font(.headline)
                        .foregroundColor(Theme.statusColor(pressure: vm.displayMemPressure))
                    Text("System Uptime: \(vm.uptimeString)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Hardware State Indicator (Temperature indicator)
                HStack(spacing: 6) {
                    Image(systemName: "thermometer.sun.fill")
                        .foregroundColor(thermalColor(state: vm.displayThermalState))
                    Text(thermalString(state: vm.displayThermalState))
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(thermalColor(state: vm.displayThermalState))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
                
                // Mini HUD Toggle
                Button(action: {
                    showMiniHUD.toggle()
                    if showMiniHUD {
                        openWindow(id: "hud")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            NSApp.windows.first { $0.level == .floating && $0.styleMask.contains(.borderless) }?.makeKeyAndOrderFront(nil)
                        }
                    } else {
                        NSApp.windows.forEach { window in
                            if window.level == .floating && window.styleMask.contains(.borderless) {
                                window.close()
                            }
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: showMiniHUD ? "macwindow.badge.minus" : "macwindow.badge.plus")
                        Text(showMiniHUD ? "Hide HUD" : "Show HUD")
                    }
                    .font(.subheadline)
                    .bold()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(showMiniHUD ? Theme.amethyst.opacity(0.2) : Color.white.opacity(0.05))
                    .foregroundColor(showMiniHUD ? Theme.amethyst : .primary)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .glassCardStyle()
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                VStack(alignment: .leading, spacing: 10) { HStack { Image(systemName: "cpu").font(.title2).foregroundColor(Theme.statusColor(pressure: vm.displayCpu)); Text("CPU LOAD").font(.system(.subheadline, design: .rounded)).bold().foregroundColor(.secondary); Spacer(); Text(String(format: "%.1f%%", vm.displayCpu)).font(.system(.title3, design: .rounded)).bold().foregroundColor(Theme.statusColor(pressure: vm.displayCpu)) }; SmoothLiveChart(data: vm.cpuHistory, color: Theme.statusColor(pressure: vm.overallCpu), maxVal: 100.0).frame(height: 60) }.glassCardStyle()
                VStack(alignment: .leading, spacing: 10) { HStack { Image(systemName: "display").font(.title2).foregroundColor(Theme.amethyst); Text("GPU UTILIZATION").font(.system(.subheadline, design: .rounded)).bold().foregroundColor(.secondary); Spacer(); Text(String(format: "%.1f%%", vm.displayGpu)).font(.system(.title3, design: .rounded)).bold().foregroundColor(Theme.amethyst) }; SmoothLiveChart(data: vm.gpuHistory, color: Theme.amethyst, maxVal: 100.0).frame(height: 60) }.glassCardStyle()
                VStack(alignment: .leading, spacing: 10) { HStack { Image(systemName: "memorychip").font(.title2).foregroundColor(Theme.statusColor(pressure: vm.displayMemPressure)); Text("MEMORY PRESSURE").font(.system(.subheadline, design: .rounded)).bold().foregroundColor(.secondary); Spacer(); Text(String(format: "%.1f%%", vm.displayMemPressure)).font(.system(.title3, design: .rounded)).bold().foregroundColor(Theme.statusColor(pressure: vm.displayMemPressure)) }; SmoothLiveChart(data: vm.memHistory, color: Theme.statusColor(pressure: vm.memoryInfo?.pressurePercentage ?? 0.0), maxVal: 100.0).frame(height: 60) }.glassCardStyle()
                VStack(alignment: .leading, spacing: 10) { HStack { Image(systemName: "wifi").font(.title2).foregroundColor(Theme.ocean); Text("NETWORK SPEED").font(.system(.subheadline, design: .rounded)).bold().foregroundColor(.secondary); Spacer() }; HStack { VStack(alignment: .leading) { Text("Download").font(.caption2).foregroundColor(.secondary); Text(formatBytes(vm.displayNetInRate) + "/s").font(.system(.subheadline, design: .rounded)).bold().foregroundColor(Theme.ocean) }; Spacer(); VStack(alignment: .trailing) { Text("Upload").font(.caption2).foregroundColor(.secondary); Text(formatBytes(vm.displayNetOutRate) + "/s").font(.system(.subheadline, design: .rounded)).bold() } }; SmoothLiveChart(data: vm.netDownloadHistory, color: Theme.ocean).frame(height: 60) }.glassCardStyle()
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
                            if let icon = process.icon {
                                NSImageViewRepresentable(image: icon)
                                    .frame(width: 24, height: 24)
                            } else {
                                Image(systemName: "apple.terminal").frame(width: 24, height: 24).foregroundColor(.secondary)
                            }
                            Text(process.name).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                            Text("\(process.pid)").frame(width: 50, alignment: .leading).font(.caption.monospacedDigit()).foregroundColor(.secondary)
                            Text(String(format: "%.1f%%", process.cpuPercent)).frame(width: 60, alignment: .trailing).font(.caption.monospacedDigit()).foregroundColor(process.cpuPercent > 50.0 ? .red : .primary)
                            Text(formatBytes(Double(process.memoryBytes))).frame(width: 80, alignment: .trailing).font(.caption.monospacedDigit())
                            
                            // Kill Switch
                            Button(action: {
                                vm.processMonitor.killProcess(pid: process.pid)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .frame(width: 20)
                            .help("Force Quit \(process.name)")
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal)
                        .background(Color.white.opacity(0.02))
                        .cornerRadius(6)
                    }
                }
            }
        }
        .glassCardStyle()
    }

    // MARK: - CPU Details View
    private var cpuDetailsView: some View {
        VStack(spacing: 20) {
            HStack { VStack(alignment: .leading, spacing: 5) { Text("Overall CPU Load").font(.headline); Text("Total process scheduling overhead").font(.subheadline).foregroundColor(.secondary) }; Spacer(); Text(String(format: "%.1f%%", vm.displayCpu)).font(.system(.largeTitle, design: .rounded)).bold().foregroundColor(Theme.statusColor(pressure: vm.displayCpu)) }.glassCardStyle()
            VStack(alignment: .leading, spacing: 12) {
                Text("Processor Cores Activity").font(.system(.subheadline, design: .rounded)).bold().foregroundColor(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 12) {
                    ForEach(0..<vm.displayCpuCoreUsages.count, id: \.self) { idx in
                        let usage = vm.displayCpuCoreUsages[idx]
                        VStack(alignment: .leading, spacing: 6) { Text("Core \(idx)").font(.caption).foregroundColor(.secondary); Text(String(format: "%.1f%%", usage)).font(.system(.title3, design: .rounded)).bold().foregroundColor(Theme.statusColor(pressure: usage)); GeometryReader { geometry in ZStack(alignment: .leading) { RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.1)); RoundedRectangle(cornerRadius: 3).fill(Theme.statusColor(pressure: usage)).frame(width: geometry.size.width * CGFloat(usage / 100.0)).animation(.linear(duration: 0.8), value: usage) } }.frame(height: 6) }.padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Theme.statusColor(pressure: usage).opacity(0.04 + (usage / 100.0) * 0.12))).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
                    }
                }
            }.glassCardStyle()
        }
    }

    // MARK: - GPU Details View
    private var gpuDetailsView: some View { VStack(spacing: 20) { HStack { VStack(alignment: .leading, spacing: 5) { Text("Apple Silicon GPU Utilization").font(.headline); Text("Hardware accelerator performance statistics").font(.subheadline).foregroundColor(.secondary) }; Spacer(); Text(String(format: "%.1f%%", vm.displayGpu)).font(.system(.largeTitle, design: .rounded)).bold().foregroundColor(Theme.amethyst) }.glassCardStyle(); SmoothLiveChart(data: vm.gpuHistory, color: Theme.amethyst, maxVal: 100.0).frame(height: 200).glassCardStyle() } }

    // MARK: - Memory Details View
    private var memoryDetailsView: some View { VStack(spacing: 20) { if let m = vm.memoryInfo { HStack(spacing: 40) { ZStack { Circle().stroke(Color.white.opacity(0.05), lineWidth: 16).frame(width: 140, height: 140); Circle().trim(from: 0.0, to: CGFloat(vm.displayMemPressure / 100.0)).stroke(AngularGradient(gradient: Gradient(colors: [Theme.statusColor(pressure: vm.displayMemPressure), Theme.statusColor(pressure: vm.displayMemPressure).opacity(0.6)]), center: .center), style: StrokeStyle(lineWidth: 16, lineCap: .round)).rotationEffect(Angle(degrees: -90)).frame(width: 140, height: 140); VStack { Text(String(format: "%.0f%%", vm.displayMemPressure)).font(.system(.largeTitle, design: .rounded)).bold().foregroundColor(Theme.statusColor(pressure: vm.displayMemPressure)); Text("Pressure").font(.caption2).foregroundColor(.secondary) } }.padding(.leading, 10); VStack(alignment: .leading, spacing: 10) { Text("Memory Breakdown").font(.headline); Group { breakdownRow(label: "Active Memory", val: m.activeGB, color: Theme.amber); breakdownRow(label: "Wired System", val: m.wiredGB, color: .orange); breakdownRow(label: "Compressed", val: m.compressedGB, color: Theme.ocean); breakdownRow(label: "Free/Cached", val: m.freeGB, color: Theme.sage) }; Divider().padding(.vertical, 4); HStack { Text("Total Installed RAM").font(.caption).foregroundColor(.secondary); Spacer(); Text(String(format: "%.1f GB", m.totalGB)).font(.subheadline).bold() } } }.glassCardStyle() } } }
    private func breakdownRow(label: String, val: Double, color: Color) -> some View { HStack { Circle().fill(color).frame(width: 8, height: 8); Text(label).font(.subheadline).foregroundColor(.secondary); Spacer(); Text(String(format: "%.2f GB", val)).font(.system(.subheadline, design: .rounded)).bold() } }

    // MARK: - Disk Details View
    private var diskDetailsView: some View { VStack(spacing: 20) { if let d = vm.diskSpace { VStack(alignment: .leading, spacing: 10) { Text("Macintosh HD Capacity").font(.headline); GeometryReader { geometry in ZStack(alignment: .leading) { RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)); RoundedRectangle(cornerRadius: 6).fill(Theme.terracotta).frame(width: geometry.size.width * CGFloat(d.usedGB / d.totalGB)) } }.frame(height: 12); HStack { Text(String(format: "%.1f GB Used", d.usedGB)).font(.caption).foregroundColor(Theme.terracotta); Spacer(); Text(String(format: "%.1f GB Free", d.freeGB)).font(.caption).foregroundColor(.secondary); Spacer(); Text(String(format: "%.1f GB Total", d.totalGB)).font(.caption).bold() } }.glassCardStyle() }; VStack(alignment: .leading, spacing: 12) { Text("Disk Read / Write Throughput").font(.system(.subheadline, design: .rounded)).bold().foregroundColor(.secondary); HStack(spacing: 20) { VStack(alignment: .leading) { Text("Active Reads").font(.caption).foregroundColor(.secondary); Text(formatBytes(vm.displayDiskReadRate) + "/s").font(.title3).bold().foregroundColor(Theme.terracotta) }; VStack(alignment: .leading) { Text("Active Writes").font(.caption).foregroundColor(.secondary); Text(formatBytes(vm.displayDiskWriteRate) + "/s").font(.title3).bold().foregroundColor(.secondary) } }; SmoothLiveChart(data: vm.diskReadHistory, color: Theme.terracotta).frame(height: 120) }.glassCardStyle() } }

    // MARK: - Network Details View
    private var networkDetailsView: some View { VStack(spacing: 20) { VStack(alignment: .leading, spacing: 12) { Text("Network Activity (Download/Upload)").font(.system(.subheadline, design: .rounded)).bold().foregroundColor(.secondary); HStack(spacing: 20) { VStack(alignment: .leading) { Text("Download Speed").font(.caption).foregroundColor(.secondary); Text(formatBytes(vm.displayNetInRate) + "/s").font(.title3).bold().foregroundColor(Theme.ocean) }; VStack(alignment: .leading) { Text("Upload Speed").font(.caption).foregroundColor(.secondary); Text(formatBytes(vm.displayNetOutRate) + "/s").font(.title3).bold().foregroundColor(.secondary) } }; SmoothLiveChart(data: vm.netDownloadHistory, color: Theme.ocean).frame(height: 120) }.glassCardStyle() } }

    private func formatBytes(_ bytes: Double) -> String { let kb = 1024.0; let mb = kb * 1024.0; let gb = mb * 1024.0; if bytes >= gb { return String(format: "%.2f GB", bytes / gb) } else if bytes >= mb { return String(format: "%.2f MB", bytes / mb) } else if bytes >= kb { return String(format: "%.1f KB", bytes / kb) } else { return "\(Int(bytes)) B" } }
    
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

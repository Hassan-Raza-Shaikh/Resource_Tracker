import SwiftUI

// MARK: - Color Palette
struct Theme {
    static let sage = Color(red: 0.38, green: 0.49, blue: 0.43)       // CPU (Nordic Sage)
    static let amber = Color(red: 0.82, green: 0.61, blue: 0.33)      // Memory (Warm Amber)
    static let terracotta = Color(red: 0.76, green: 0.44, blue: 0.32) // Disk (Copper Terracotta)
    static let ocean = Color(red: 0.34, green: 0.47, blue: 0.54)       // Network (Ocean Slate)
    static let backgroundDark = Color(red: 0.08, green: 0.08, blue: 0.09)
    static let textLight = Color(red: 0.95, green: 0.93, blue: 0.88)
}

// MARK: - Glass Style Modifier
struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.02),
                                Color.black.opacity(0.18),
                                Color.white.opacity(0.06)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}

extension View {
    func glassCardStyle() -> some View {
        self.modifier(GlassCard())
    }
}

// MARK: - View Model
class MonitorViewModel: ObservableObject {
    private let cpuMonitor = CPUMonitor()
    private let memMonitor = MemoryMonitor()
    private let netMonitor = NetworkMonitor()
    private let diskMonitor = DiskMonitor()
    private var timer: Timer?

    @Published var cpuCoreUsages: [Double] = []
    @Published var overallCpu: Double = 0.0
    
    @Published var memoryInfo: MemoryMonitor.MemoryInfo? = nil
    
    @Published var netInRate: Double = 0.0
    @Published var netOutRate: Double = 0.0
    
    @Published var diskReadRate: Double = 0.0
    @Published var diskWriteRate: Double = 0.0
    @Published var diskSpace: (totalGB: Double, freeGB: Double, usedGB: Double)? = nil
    
    // History (last 30 samples)
    @Published var cpuHistory: [Double] = Array(repeating: 0.0, count: 30)
    @Published var memHistory: [Double] = Array(repeating: 0.0, count: 30)
    @Published var netDownloadHistory: [Double] = Array(repeating: 0.0, count: 30)
    @Published var netUploadHistory: [Double] = Array(repeating: 0.0, count: 30)
    @Published var diskReadHistory: [Double] = Array(repeating: 0.0, count: 30)
    @Published var diskWriteHistory: [Double] = Array(repeating: 0.0, count: 30)

    init() {
        // Initial fetch to establish starting baseline rates
        _ = cpuMonitor.getCPUUsages()
        _ = netMonitor.getNetworkRates()
        _ = diskMonitor.getDiskRates()
        
        updateStats()
        
        // Poll every 1.0 second
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
    }

    deinit {
        timer?.invalidate()
    }

    private func updateStats() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 1. CPU
            let cores = self.cpuMonitor.getCPUUsages()
            self.cpuCoreUsages = cores
            if !cores.isEmpty {
                self.overallCpu = cores.reduce(0.0, +) / Double(cores.count)
            } else {
                self.overallCpu = 0.0
            }
            self.cpuHistory.removeFirst()
            self.cpuHistory.append(self.overallCpu)
            
            // 2. Memory
            if let mem = self.memMonitor.getMemoryInfo() {
                self.memoryInfo = mem
                self.memHistory.removeFirst()
                self.memHistory.append(mem.pressurePercentage)
            }
            
            // 3. Network
            let (inRate, outRate) = self.netMonitor.getNetworkRates()
            self.netInRate = inRate
            self.netOutRate = outRate
            self.netDownloadHistory.removeFirst()
            self.netDownloadHistory.append(inRate)
            self.netUploadHistory.removeFirst()
            self.netUploadHistory.append(outRate)
            
            // 4. Disk
            let (readRate, writeRate) = self.diskMonitor.getDiskRates()
            self.diskReadRate = readRate
            self.diskWriteRate = writeRate
            self.diskReadHistory.removeFirst()
            self.diskReadHistory.append(readRate)
            self.diskWriteHistory.removeFirst()
            self.diskWriteHistory.append(writeRate)
            
            if let space = self.diskMonitor.getDiskSpaceInfo() {
                self.diskSpace = space
            }
        }
    }
}

// MARK: - Custom Area Chart
struct LiveChart: View {
    var data: [Double]
    var color: Color
    var maxVal: Double? = nil
    
    var body: some View {
        GeometryReader { geo in
            let peak = maxVal ?? (data.max() ?? 1.0 == 0 ? 1.0 : data.max() ?? 1.0)
            let limit = peak <= 0 ? 1.0 : peak
            
            Path { path in
                guard data.count > 1 else { return }
                let stepX = geo.size.width / CGFloat(data.count - 1)
                
                let startY = geo.size.height - CGFloat(data[0] / limit) * geo.size.height
                path.move(to: CGPoint(x: 0, y: startY))
                
                for i in 1..<data.count {
                    let x = CGFloat(i) * stepX
                    let y = geo.size.height - CGFloat(data[i] / limit) * geo.size.height
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(
                LinearGradient(
                    gradient: Gradient(colors: [color, color.opacity(0.6)]),
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
            .background(
                Path { path in
                    guard data.count > 1 else { return }
                    let stepX = geo.size.width / CGFloat(data.count - 1)
                    
                    path.move(to: CGPoint(x: 0, y: geo.size.height))
                    let startY = geo.size.height - CGFloat(data[0] / limit) * geo.size.height
                    path.addLine(to: CGPoint(x: 0, y: startY))
                    
                    for i in 1..<data.count {
                        let x = CGFloat(i) * stepX
                        let y = geo.size.height - CGFloat(data[i] / limit) * geo.size.height
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [color.opacity(0.12), color.opacity(0.0)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            )
        }
    }
}

// MARK: - Main Content View
public struct ContentView: View {
    @StateObject private var vm = MonitorViewModel()
    @State private var selectedTab: String? = "Dashboard"

    public init() {}

    public var body: some View {
        NavigationSplitView {
            // Sidebar Layout (Notes/Reminders style)
            List(selection: $selectedTab) {
                Section(header: Text("Overview").foregroundColor(.secondary)) {
                    NavigationLink(value: "Dashboard") {
                        Label("Dashboard", systemImage: "square.grid.2x2")
                    }
                }
                
                Section(header: Text("Monitors").foregroundColor(.secondary)) {
                    NavigationLink(value: "CPU") {
                        HStack {
                            Label("CPU", systemImage: "cpu")
                            Spacer()
                            Text(String(format: "%.0f%%", vm.overallCpu))
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.sage.opacity(0.2))
                                .cornerRadius(8)
                        }
                    }
                    
                    NavigationLink(value: "Memory") {
                        HStack {
                            Label("Memory", systemImage: "memorychip")
                            Spacer()
                            Text(String(format: "%.0f%%", vm.memoryInfo?.pressurePercentage ?? 0.0))
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.amber.opacity(0.2))
                                .cornerRadius(8)
                        }
                    }
                    
                    NavigationLink(value: "Disk") {
                        HStack {
                            Label("Disk I/O", systemImage: "internaldrive")
                            Spacer()
                            Text(formatBytes(vm.diskReadRate + vm.diskWriteRate) + "/s")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    NavigationLink(value: "Network") {
                        HStack {
                            Label("Network", systemImage: "wifi")
                            Spacer()
                            Text(formatBytes(vm.netInRate) + "/s")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 250)
            
        } detail: {
            // Details Pane with dynamic sections
            ScrollView {
                VStack(spacing: 20) {
                    if selectedTab == "Dashboard" {
                        dashboardView
                    } else if selectedTab == "CPU" {
                        cpuDetailsView
                    } else if selectedTab == "Memory" {
                        memoryDetailsView
                    } else if selectedTab == "Disk" {
                        diskDetailsView
                    } else if selectedTab == "Network" {
                        networkDetailsView
                    }
                }
                .padding(24)
            }
            .background(
                VisualEffectView(material: .windowBackground, blendingMode: .behindWindow)
                    .ignoresSafeArea()
            )
            .navigationTitle(selectedTab ?? "Resource Tracker")
            .navigationSubtitle(Text("Real-time System Activity"))
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(WindowAccessor { window in
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
        })
    }


    // MARK: - Dashboard View
    private var dashboardView: some View {
        VStack(spacing: 20) {
            // Header Stats Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                // CPU Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "cpu")
                            .font(.title2)
                            .foregroundColor(Theme.sage)
                        Text("CPU LOAD")
                            .font(.system(.subheadline, design: .rounded))
                            .bold()
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1f%%", vm.overallCpu))
                            .font(.system(.title3, design: .rounded))
                            .bold()
                            .foregroundColor(Theme.sage)
                    }
                    
                    LiveChart(data: vm.cpuHistory, color: Theme.sage, maxVal: 100.0)
                        .frame(height: 60)
                    
                    Text("\(vm.cpuCoreUsages.count) Cores Detected")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .glassCardStyle()
                
                // Memory Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "memorychip")
                            .font(.title2)
                            .foregroundColor(Theme.amber)
                        Text("MEMORY PRESSURE")
                            .font(.system(.subheadline, design: .rounded))
                            .bold()
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1f%%", vm.memoryInfo?.pressurePercentage ?? 0.0))
                            .font(.system(.title3, design: .rounded))
                            .bold()
                            .foregroundColor(Theme.amber)
                    }
                    
                    LiveChart(data: vm.memHistory, color: Theme.amber, maxVal: 100.0)
                        .frame(height: 60)
                    
                    if let m = vm.memoryInfo {
                        Text(String(format: "Using %.1f GB of %.1f GB", m.usedGB, m.totalGB))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Calculating memory statistics...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .glassCardStyle()
                
                // Disk Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "internaldrive")
                            .font(.title2)
                            .foregroundColor(Theme.terracotta)
                        Text("DISK THROUGHPUT")
                            .font(.system(.subheadline, design: .rounded))
                            .bold()
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Read").font(.caption2).foregroundColor(.secondary)
                            Text(formatBytes(vm.diskReadRate) + "/s").font(.system(.subheadline, design: .rounded)).bold().foregroundColor(Theme.terracotta)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("Write").font(.caption2).foregroundColor(.secondary)
                            Text(formatBytes(vm.diskWriteRate) + "/s").font(.system(.subheadline, design: .rounded)).bold()
                        }
                    }
                    
                    LiveChart(data: vm.diskReadHistory, color: Theme.terracotta)
                        .frame(height: 60)
                }
                .glassCardStyle()
                
                // Network Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "wifi")
                            .font(.title2)
                            .foregroundColor(Theme.ocean)
                        Text("NETWORK SPEED")
                            .font(.system(.subheadline, design: .rounded))
                            .bold()
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Download").font(.caption2).foregroundColor(.secondary)
                            Text(formatBytes(vm.netInRate) + "/s").font(.system(.subheadline, design: .rounded)).bold().foregroundColor(Theme.ocean)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("Upload").font(.caption2).foregroundColor(.secondary)
                            Text(formatBytes(vm.netOutRate) + "/s").font(.system(.subheadline, design: .rounded)).bold()
                        }
                    }
                    
                    LiveChart(data: vm.netDownloadHistory, color: Theme.ocean)
                        .frame(height: 60)
                }
                .glassCardStyle()
            }
        }
    }

    // MARK: - CPU Details View
    private var cpuDetailsView: some View {
        VStack(spacing: 20) {
            // General CPU Stats card
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Overall CPU Load").font(.headline)
                    Text("Total process scheduling overhead").font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
                Text(String(format: "%.1f%%", vm.overallCpu))
                    .font(.system(.largeTitle, design: .rounded))
                    .bold()
                    .foregroundColor(Theme.sage)
            }
            .glassCardStyle()
            
            // CPU Cores Grid
            VStack(alignment: .leading, spacing: 12) {
                Text("Processor Cores Activity")
                    .font(.system(.subheadline, design: .rounded))
                    .bold()
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 12) {
                    ForEach(0..<vm.cpuCoreUsages.count, id: \.self) { idx in
                        let usage = vm.cpuCoreUsages[idx]
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Core \(idx)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.1f%%", usage))
                                .font(.system(.title3, design: .rounded))
                                .bold()
                                .foregroundColor(Theme.sage)
                            
                            // Visual indicator bar
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.white.opacity(0.1))
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Theme.sage)
                                        .frame(width: geometry.size.width * CGFloat(usage / 100.0))
                                }
                            }
                            .frame(height: 6)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Theme.sage.opacity(0.04 + (usage / 100.0) * 0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                    }
                }
            }
            .glassCardStyle()
        }
    }

    // MARK: - Memory Details View
    private var memoryDetailsView: some View {
        VStack(spacing: 20) {
            if let m = vm.memoryInfo {
                HStack(spacing: 40) {
                    // Gauge ring
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.05), lineWidth: 16)
                            .frame(width: 140, height: 140)
                        
                        Circle()
                            .trim(from: 0.0, to: CGFloat(m.pressurePercentage / 100.0))
                            .stroke(
                                AngularGradient(
                                    gradient: Gradient(colors: [Theme.amber, Theme.amber.opacity(0.6)]),
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 16, lineCap: .round)
                            )
                            .rotationEffect(Angle(degrees: -90))
                            .frame(width: 140, height: 140)
                            .animation(.linear(duration: 0.5), value: m.pressurePercentage)
                        
                        VStack {
                            Text(String(format: "%.0f%%", m.pressurePercentage))
                                .font(.system(.largeTitle, design: .rounded))
                                .bold()
                                .foregroundColor(Theme.amber)
                            Text("Pressure")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.leading, 10)
                    
                    // Stats Breakdown
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Memory Breakdown").font(.headline)
                        
                        Group {
                            breakdownRow(label: "Active Memory", val: m.activeGB, color: Theme.amber)
                            breakdownRow(label: "Wired System", val: m.wiredGB, color: .orange)
                            breakdownRow(label: "Compressed", val: m.compressedGB, color: Theme.ocean)
                            breakdownRow(label: "Free/Cached", val: m.freeGB, color: Theme.sage)
                        }
                        
                        Divider().padding(.vertical, 4)
                        
                        HStack {
                            Text("Total Installed RAM").font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.1f GB", m.totalGB)).font(.subheadline).bold()
                        }
                    }
                }
                .glassCardStyle()
            } else {
                Text("Waiting for Memory Metrics...").glassCardStyle()
            }
        }
    }
    
    private func breakdownRow(label: String, val: Double, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(String(format: "%.2f GB", val))
                .font(.system(.subheadline, design: .rounded))
                .bold()
        }
    }

    // MARK: - Disk Details View
    private var diskDetailsView: some View {
        VStack(spacing: 20) {
            // Storage Capacity Bar
            if let d = vm.diskSpace {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Macintosh HD Capacity").font(.headline)
                    
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.08))
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Theme.terracotta)
                                .frame(width: geometry.size.width * CGFloat(d.usedGB / d.totalGB))
                        }
                    }
                    .frame(height: 12)
                    
                    HStack {
                        Text(String(format: "%.1f GB Used", d.usedGB))
                            .font(.caption)
                            .foregroundColor(Theme.terracotta)
                        Spacer()
                        Text(String(format: "%.1f GB Free", d.freeGB))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1f GB Total", d.totalGB))
                            .font(.caption)
                            .bold()
                    }
                }
                .glassCardStyle()
            }
            
            // Disk Speed Live Graph
            VStack(alignment: .leading, spacing: 12) {
                Text("Disk Read / Write Throughput")
                    .font(.system(.subheadline, design: .rounded))
                    .bold()
                    .foregroundColor(.secondary)
                
                HStack(spacing: 20) {
                    VStack(alignment: .leading) {
                        Text("Active Reads").font(.caption).foregroundColor(.secondary)
                        Text(formatBytes(vm.diskReadRate) + "/s").font(.title3).bold().foregroundColor(Theme.terracotta)
                    }
                    VStack(alignment: .leading) {
                        Text("Active Writes").font(.caption).foregroundColor(.secondary)
                        Text(formatBytes(vm.diskWriteRate) + "/s").font(.title3).bold().foregroundColor(.secondary)
                    }
                }
                
                LiveChart(data: vm.diskReadHistory, color: Theme.terracotta)
                    .frame(height: 120)
            }
            .glassCardStyle()
        }
    }

    // MARK: - Network Details View
    private var networkDetailsView: some View {
        VStack(spacing: 20) {
            // Transfer speed Live Graph
            VStack(alignment: .leading, spacing: 12) {
                Text("Network Activity (Download/Upload)")
                    .font(.system(.subheadline, design: .rounded))
                    .bold()
                    .foregroundColor(.secondary)
                
                HStack(spacing: 20) {
                    VStack(alignment: .leading) {
                        Text("Download Speed").font(.caption).foregroundColor(.secondary)
                        Text(formatBytes(vm.netInRate) + "/s").font(.title3).bold().foregroundColor(Theme.ocean)
                    }
                    VStack(alignment: .leading) {
                        Text("Upload Speed").font(.caption).foregroundColor(.secondary)
                        Text(formatBytes(vm.netOutRate) + "/s").font(.title3).bold().foregroundColor(.secondary)
                    }
                }
                
                LiveChart(data: vm.netDownloadHistory, color: Theme.ocean)
                    .frame(height: 120)
            }
            .glassCardStyle()
        }
    }

    // MARK: - Helper Data Formatter
    private func formatBytes(_ bytes: Double) -> String {
        let kb = 1024.0
        let mb = kb * 1024.0
        let gb = mb * 1024.0
        
        if bytes >= gb {
            return String(format: "%.2f GB", bytes / gb)
        } else if bytes >= mb {
            return String(format: "%.2f MB", bytes / mb)
        } else if bytes >= kb {
            return String(format: "%.1f KB", bytes / kb)
        } else {
            return "\(Int(bytes)) B"
        }
    }
}

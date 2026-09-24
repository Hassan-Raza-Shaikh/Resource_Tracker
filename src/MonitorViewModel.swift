import Foundation
import Observation

/// One sparkline sample. `id` is the sample's position in the fixed window, so two
/// histories with the same values compare equal and the view can skip a redraw.
struct ChartDataPoint: Identifiable, Equatable {
    let id: Int
    let value: Double
}

enum StatusLevel: Equatable { case nominal, elevated, critical }

/// The one-line health summary shown in the header and window subtitle.
struct SystemStatus: Equatable {
    let text: String
    let level: StatusLevel

    /// Ordered by severity: heat first (it throttles everything), then memory pressure, then CPU.
    static func evaluate(thermal: ProcessInfo.ThermalState, pressure: MemoryPressure, cpu: Double) -> SystemStatus {
        switch thermal {
        case .critical: return .init(text: "Your Mac is very hot and is slowing down to cool off.", level: .critical)
        case .serious: return .init(text: "Your Mac is running hot and may slow down.", level: .elevated)
        default: break
        }
        switch pressure {
        case .critical: return .init(text: "Memory is critically low. Quit apps you aren’t using.", level: .critical)
        case .warning: return .init(text: "Memory is under pressure.", level: .elevated)
        case .normal: break
        }
        if cpu > 85 { return .init(text: "Your Mac is under heavy load.", level: .elevated) }
        if cpu > 65 { return .init(text: "Working hard right now.", level: .elevated) }
        return .init(text: "Cruising smoothly.", level: .nominal)
    }
}

/// Keeps a rolling-window peak so throughput bars have a stable reference scale.
/// Normalising against the instantaneous max(in, out) pins one bar at 100% and
/// makes both swing every tick on idle background traffic.
struct PeakTracker {
    private var window: [Double]
    private var cursor = 0
    private let floor: Double

    /// `floor` is the smallest full-scale value; traffic below it reads as a sliver.
    init(floor: Double, windowLength: Int = MonitorViewModel.historyLength) {
        self.floor = floor
        self.window = Array(repeating: 0, count: windowLength)
    }

    /// Max over the window (or the floor). It only changes when a sample enters or
    /// leaves the window, so bars hold still while traffic is steady.
    var peak: Double { max(window.max() ?? 0, floor) }

    mutating func update(_ values: Double...) {
        window[cursor] = values.max() ?? 0
        cursor = (cursor + 1) % window.count
    }

    /// Bar fill in 5% steps: below that a change is invisible, and animating it only burns frames.
    func fraction(_ value: Double) -> Double {
        Theme.quantize(min(value / peak, 1.0), step: 0.05)
    }
}

/// Samples the system once a second and publishes display-ready values.
///
/// Two rules keep this cheap:
/// - Every published value is stored at the precision it is displayed, and only
///   assigned when it changes. With @Observable any assignment invalidates the views
///   reading it, so a 12.31% → 12.34% CPU change must never reach a view showing "12%".
/// - Each surface (dashboard window, menu bar, HUD) reads its own values, published
///   only while that surface is on screen. Changing a value a hidden view reads still
///   costs a full layout of its window, so with nothing visible almost nothing is
///   published. History keeps recording regardless and appears in one go when the
///   dashboard is shown again.
@Observable
final class MonitorViewModel {
    static let historyLength = 30

    enum Surface { case dashboard, menuBar, hud }

    /// What the menu bar and HUD show. One value, so neither reads dashboard state.
    struct Glance: Equatable {
        var cpu = 0, memory = 0, gpu = 0
        var download = Format.rate(0), upload = Format.rate(0)
    }

    @ObservationIgnored private let cpuMonitor = CPUMonitor()
    @ObservationIgnored private let memMonitor = MemoryMonitor()
    @ObservationIgnored private let netMonitor = NetworkMonitor()
    @ObservationIgnored private let diskMonitor = DiskMonitor()
    @ObservationIgnored private let gpuMonitor = GPUMonitor()
    let processMonitor = ProcessMonitor()

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var tick = 0
    @ObservationIgnored private var visibleSurfaces: Set<Surface> = [.dashboard]

    // MARK: Always published — every surface shows these, and they rarely change
    var status = SystemStatus(text: "Cruising smoothly.", level: .nominal)
    var memoryPressure: MemoryPressure = .normal

    // MARK: Menu bar & HUD — published while either is open
    var glance = Glance()

    // MARK: Dashboard — published while the dashboard window is visible
    var cpuPercent: Int = 0             // whole-percent readouts (sidebar badges, ring gauge)
    var gpuPercent: Int = 0
    var memPercent: Int = 0
    var netInText = Format.rate(0)
    var netOutText = Format.rate(0)
    var cpu: Double = 0                 // 0.1% precision
    var coreUsages: [Double] = []
    var gpu: Double = 0
    var cpuHistory: [ChartDataPoint] = []
    var gpuHistory: [ChartDataPoint] = []

    var memoryInfo: MemoryMonitor.MemoryInfo? = nil     // 0.01 GB precision, for the Memory tab
    var memorySummary: MemoryMonitor.MemoryInfo? = nil  // 0.1 GB precision, for the dashboard card

    var netInFraction: Double = 0
    var netOutFraction: Double = 0
    var netInHistory: [ChartDataPoint] = []
    var netOutHistory: [ChartDataPoint] = []

    var diskReadText = Format.rate(0)
    var diskWriteText = Format.rate(0)
    var diskReadFraction: Double = 0
    var diskWriteFraction: Double = 0
    var diskReadHistory: [ChartDataPoint] = []
    var diskWriteHistory: [ChartDataPoint] = []
    var diskSpace: DiskSpace? = nil

    var thermalState: ProcessInfo.ThermalState = .nominal
    var uptime: String = ""

    // MARK: Buffered state (never observed)
    private struct Reading {
        var cores: [Double] = []
        var cpu: Double = 0
        var gpu: Double = 0
        var memory: MemoryMonitor.MemoryInfo?
        var netIn: Double = 0, netOut: Double = 0
        var diskRead: Double = 0, diskWrite: Double = 0
        var diskSpace: DiskSpace?
        var thermal: ProcessInfo.ThermalState = .nominal
    }

    /// Only real samples: graphs fill in from the right after launch rather than
    /// showing half a minute of zeros that never happened.
    private struct Histories {
        var cpu: [Double] = [], gpu: [Double] = []
        var netIn: [Double] = [], netOut: [Double] = []
        var diskRead: [Double] = [], diskWrite: [Double] = []
    }

    /// Minimum full-scale values for throughput graphs and bars: idle background
    /// traffic below these reads as a sliver, not a spike.
    static let networkScaleFloor = 512.0 * 1024
    static let diskScaleFloor = 4.0 * 1024 * 1024

    @ObservationIgnored private var latest = Reading()
    @ObservationIgnored private var histories = Histories()
    @ObservationIgnored private var netPeak = PeakTracker(floor: MonitorViewModel.networkScaleFloor)
    @ObservationIgnored private var diskPeak = PeakTracker(floor: MonitorViewModel.diskScaleFloor)

    init() {
        publishDashboard()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.update() }
        // Tolerance lets macOS coalesce our wakeups with others' (a real energy win for a
        // background app); .common keeps graphs live while a window is being resized.
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        update()
    }

    deinit {
        timer?.invalidate()
    }

    /// Surfaces report here as they appear and disappear (for the dashboard: also when
    /// minimised, covered, or on a locked screen). A surface that becomes visible gets
    /// the latest values immediately rather than waiting for the next tick.
    func setVisible(_ surface: Surface, _ visible: Bool) {
        guard visibleSurfaces.contains(surface) != visible else { return }
        if visible { visibleSurfaces.insert(surface) } else { visibleSurfaces.remove(surface) }
        #if DEBUG
        Trace.note("\(surface) visible=\(visible)")
        #endif
        guard visible else { return }
        switch surface {
        case .dashboard: publishDashboard()
        case .menuBar, .hud: publishGlance()
        }
    }

    // MARK: Sampling

    private func update() {
        defer { tick += 1 }

        var r = Reading()
        r.cores = cpuMonitor.getCPUUsages()
        r.cpu = r.cores.isEmpty ? 0 : r.cores.reduce(0, +) / Double(r.cores.count)
        r.gpu = gpuMonitor.getGPUUtilization()
        r.memory = memMonitor.getMemoryInfo()
        (r.netIn, r.netOut) = netMonitor.getNetworkRates()
        (r.diskRead, r.diskWrite) = diskMonitor.getDiskRates()
        r.thermal = ProcessInfo.processInfo.thermalState
        // Capacity changes slowly and computing purgeable space isn't free: every 10s is plenty.
        r.diskSpace = tick % 10 == 0 ? (diskMonitor.getDiskSpaceInfo() ?? latest.diskSpace) : latest.diskSpace
        latest = r

        // The first tick only sets baselines (CPU, network and disk are all deltas),
        // so it has no real values to record.
        guard tick > 0 else { publishAlways(); return }

        Self.push(r.cpu, onto: &histories.cpu)
        Self.push(r.gpu, onto: &histories.gpu)
        Self.push(r.netIn, onto: &histories.netIn)
        Self.push(r.netOut, onto: &histories.netOut)
        Self.push(r.diskRead, onto: &histories.diskRead)
        Self.push(r.diskWrite, onto: &histories.diskWrite)
        netPeak.update(r.netIn, r.netOut)
        diskPeak.update(r.diskRead, r.diskWrite)

        publishAlways()
        if visibleSurfaces.contains(.dashboard) { publishDashboard() }
        if visibleSurfaces.contains(.menuBar) || visibleSurfaces.contains(.hud) { publishGlance() }

        #if DEBUG
        Trace.flush()
        #endif
    }

    // MARK: Publishing

    private func publishAlways() {
        let r = latest
        let pressure = r.memory?.pressure ?? .normal
        set(\.memoryPressure, pressure, "memoryPressure")
        set(\.status, SystemStatus.evaluate(thermal: r.thermal, pressure: pressure, cpu: r.cpu), "status")
    }

    private func publishGlance() {
        let r = latest
        set(\.glance, Glance(cpu: Int(r.cpu.rounded()),
                             memory: Int((r.memory?.usedPercentage ?? 0).rounded()),
                             gpu: Int(r.gpu.rounded()),
                             download: Format.rate(r.netIn),
                             upload: Format.rate(r.netOut)), "glance")
    }

    private func publishDashboard() {
        let r = latest
        set(\.cpuPercent, Int(r.cpu.rounded()), "cpuPercent")
        set(\.gpuPercent, Int(r.gpu.rounded()), "gpuPercent")
        set(\.memPercent, Int((r.memory?.usedPercentage ?? 0).rounded()), "memPercent")
        set(\.netInText, Format.rate(r.netIn), "netInText")
        set(\.netOutText, Format.rate(r.netOut), "netOutText")
        set(\.cpu, Theme.quantize(r.cpu, step: 0.1), "cpu")
        set(\.coreUsages, r.cores.map { Theme.quantize($0, step: 0.1) }, "coreUsages")
        set(\.gpu, r.gpu, "gpu")
        set(\.cpuHistory, Self.points(histories.cpu), "cpuHistory")
        set(\.gpuHistory, Self.points(histories.gpu), "gpuHistory")

        set(\.memoryInfo, r.memory?.rounded(toGB: 0.01), "memoryInfo")
        set(\.memorySummary, r.memory?.rounded(toGB: 0.1), "memorySummary")

        set(\.netInFraction, netPeak.fraction(r.netIn), "netInFraction")
        set(\.netOutFraction, netPeak.fraction(r.netOut), "netOutFraction")
        set(\.netInHistory, Self.points(histories.netIn), "netInHistory")
        set(\.netOutHistory, Self.points(histories.netOut), "netOutHistory")

        set(\.diskReadText, Format.rate(r.diskRead), "diskReadText")
        set(\.diskWriteText, Format.rate(r.diskWrite), "diskWriteText")
        set(\.diskReadFraction, diskPeak.fraction(r.diskRead), "diskReadFraction")
        set(\.diskWriteFraction, diskPeak.fraction(r.diskWrite), "diskWriteFraction")
        set(\.diskReadHistory, Self.points(histories.diskRead), "diskReadHistory")
        set(\.diskWriteHistory, Self.points(histories.diskWrite), "diskWriteHistory")
        set(\.diskSpace, r.diskSpace, "diskSpace")

        set(\.thermalState, r.thermal, "thermalState")
        set(\.uptime, Format.uptime(Date().timeIntervalSince(SystemInfo.bootDate)), "uptime")
    }

    private static func push(_ value: Double, onto buffer: inout [Double]) {
        buffer.append(value)
        if buffer.count > historyLength { buffer.removeFirst(buffer.count - historyLength) }
    }

    private static func points(_ values: [Double]) -> [ChartDataPoint] {
        values.enumerated().map { ChartDataPoint(id: $0.offset, value: $0.element) }
    }

    /// Assign only if changed. `name` feeds the debug trace below.
    private func set<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<MonitorViewModel, T>, _ value: T, _ name: StaticString) {
        guard self[keyPath: keyPath] != value else { return }
        self[keyPath: keyPath] = value
        #if DEBUG
        Trace.changed(name)
        #endif
    }
}

#if DEBUG
/// Launch a Debug build with RT_TRACE=1 to log which properties change each tick —
/// every change re-renders the views reading it, so this is the quickest way to spot
/// an idle-CPU regression.
private enum Trace {
    static let enabled = ProcessInfo.processInfo.environment["RT_TRACE"] != nil
    private static var names: [String] = []

    static func changed(_ name: StaticString) {
        if enabled { names.append("\(name)") }
    }

    static func note(_ message: String) {
        if enabled { FileHandle.standardError.write(Data("NOTE \(message)\n".utf8)) }
    }

    static func flush() {
        guard enabled else { return }
        FileHandle.standardError.write(Data("TICK changed=\(names.count): \(names.joined(separator: " "))\n".utf8))
        names.removeAll()
    }
}
#endif

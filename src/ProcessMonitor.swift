import Foundation
import AppKit
import Observation

@_silgen_name("proc_pidinfo")
func proc_pidinfo(_ pid: Int32, _ flavor: Int32, _ arg: UInt64, _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32

@_silgen_name("proc_name")
func proc_name(_ pid: Int32, _ buffer: UnsafeMutablePointer<CChar>, _ buffersize: UInt32) -> Int32

private let PROC_PIDTASKINFO: Int32 = 4

/// Mirror of <sys/proc_info.h> `struct proc_taskinfo`.
struct proc_taskinfo {
    var pti_virtual_size: UInt64 = 0
    var pti_resident_size: UInt64 = 0
    var pti_total_user: UInt64 = 0      // Mach absolute-time ticks, not nanoseconds
    var pti_total_system: UInt64 = 0
    var pti_threads_user: UInt64 = 0
    var pti_threads_system: UInt64 = 0
    var pti_policy: Int32 = 0
    var pti_faults: Int32 = 0
    var pti_pageins: Int32 = 0
    var pti_cow_faults: Int32 = 0
    var pti_messages_sent: Int32 = 0
    var pti_messages_received: Int32 = 0
    var pti_syscalls_mach: Int32 = 0
    var pti_syscalls_unix: Int32 = 0
    var pti_csw: Int32 = 0
    var pti_threadnum: Int32 = 0
    var pti_numrunning: Int32 = 0
    var pti_priority: Int32 = 0
}

public struct ProcessEntry: Identifiable, Equatable {
    /// The PID: stable across samples, so rows diff and animate instead of redrawing.
    public let id: Int32
    public var pid: Int32 { id }
    public let name: String
    /// Resident size — Activity Monitor's "Real Mem" column.
    public let memoryBytes: UInt64
    /// Percent of one core, EMA-smoothed. Exceeds 100 for multi-threaded work, as in Activity Monitor.
    public let cpuPercent: Double
    public let icon: NSImage?
}

public enum ProcessSortKey: String, CaseIterable, Identifiable {
    case cpu, memory
    public var id: String { rawValue }
    public var label: String { self == .cpu ? "CPU" : "Memory" }
}

/// Samples every readable process while the Processes tab is on screen.
///
/// Threading: the heavy per-PID walk runs on `sampleQueue`, and every piece of
/// sampler state below the "Sampler state" mark is touched only on that queue.
/// Published properties and the timer are main-thread only.
@Observable
public class ProcessMonitor {
    public private(set) var topProcesses: [ProcessEntry] = []
    /// False until two samples exist, i.e. until CPU figures are real deltas.
    public private(set) var hasMeasured = false
    public var sortKey: ProcessSortKey = .cpu {
        didSet { if sortKey != oldValue { rerank() } }
    }

    public static let rowLimit = 50

    // MARK: Main-thread state
    @ObservationIgnored private var updateTimer: Timer?
    @ObservationIgnored private var isSampling = false
    /// Bumped on every start/stop. A result from an older generation is dropped, so a
    /// sample in flight when polling stops can't repopulate the list afterwards.
    @ObservationIgnored private var generation = 0

    // MARK: Sampler state (sampleQueue only)
    @ObservationIgnored private let sampleQueue = DispatchQueue(label: "com.hassan.ResourceTracker.process-sampler", qos: .utility)
    @ObservationIgnored private var previousTicks: [Int32: UInt64] = [:]
    @ObservationIgnored private var smoothedCpu: [Int32: Double] = [:]
    @ObservationIgnored private var lastSampleTime: Date?
    @ObservationIgnored private var lastSample: [ProcessEntry] = []
    /// Display name and icon per PID, resolved lazily for visible rows only.
    /// `nil` values are cached too, so non-app processes aren't looked up every sample.
    @ObservationIgnored private var appInfo: [Int32: (name: String?, icon: NSImage?)] = [:]

    public init() {}

    // MARK: Lifecycle (main thread)

    /// Poll while the Processes tab is visible; stop and forget everything otherwise.
    public func setActive(_ active: Bool) {
        active ? start() : stop()
    }

    private func start() {
        guard updateTimer == nil else { return }
        generation += 1
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in self?.requestSample() }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
        requestSample()  // baseline
        // CPU% needs two samples; take the second quickly so real numbers appear at once.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.requestSample() }
    }

    private func stop() {
        guard updateTimer != nil else { return }
        updateTimer?.invalidate()
        updateTimer = nil
        generation += 1
        topProcesses = []
        hasMeasured = false
        sampleQueue.async { [self] in
            previousTicks.removeAll()
            smoothedCpu.removeAll()
            lastSampleTime = nil
            lastSample.removeAll()
            appInfo.removeAll()
        }
    }

    private func requestSample() {
        guard updateTimer != nil, !isSampling else { return }
        isSampling = true
        let gen = generation, key = sortKey
        sampleQueue.async { [weak self] in
            guard let self else { return }
            let result = self.sample(rankedBy: key)
            DispatchQueue.main.async {
                self.isSampling = false
                guard gen == self.generation, let result else { return }
                self.topProcesses = result
                self.hasMeasured = true
            }
        }
    }

    /// Re-rank the latest sample under a new sort key without waiting for the next tick.
    private func rerank() {
        guard updateTimer != nil else { return }
        let gen = generation, key = sortKey
        sampleQueue.async { [weak self] in
            guard let self, !self.lastSample.isEmpty else { return }
            let result = self.rank(self.lastSample, by: key)
            DispatchQueue.main.async {
                guard gen == self.generation else { return }
                self.topProcesses = result
            }
        }
    }

    // MARK: Sampling (sampleQueue)

    /// One pass over every process. Returns nil for the first pass, which only sets the baseline.
    private func sample(rankedBy key: ProcessSortKey) -> [ProcessEntry]? {
        let now = Date()
        let hadBaseline = lastSampleTime != nil
        let elapsed = lastSampleTime.map { now.timeIntervalSince($0) } ?? 0
        lastSampleTime = now

        var ticks: [Int32: UInt64] = [:]
        var smoothed: [Int32: Double] = [:]
        var all: [ProcessEntry] = []
        all.reserveCapacity(1024)

        let infoSize = Int32(MemoryLayout<proc_taskinfo>.stride)
        for pid in ProcessMonitor.allPids() where pid != 0 {
            var info = proc_taskinfo()
            // Other users' (and root's) processes are unreadable without privileges; skip them.
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, infoSize) == infoSize else { continue }
            let total = info.pti_total_user + info.pti_total_system
            ticks[pid] = total

            var cpu = 0.0
            if let prev = previousTicks[pid], total >= prev, elapsed > 0 {
                let seconds = Double(total - prev) * SystemInfo.nanosecondsPerTick / 1_000_000_000
                let instant = seconds / elapsed * 100
                // EMA (30% new) stops rows jumping on momentary spikes. It is seeded with the
                // first real measurement, not 0, so values are right immediately.
                cpu = smoothedCpu[pid].map { $0 * 0.7 + instant * 0.3 } ?? instant
                smoothed[pid] = cpu
            }
            all.append(ProcessEntry(id: pid, name: "", memoryBytes: info.pti_resident_size, cpuPercent: cpu, icon: nil))
        }

        previousTicks = ticks
        smoothedCpu = smoothed
        appInfo = appInfo.filter { ticks[$0.key] != nil }  // forget exited processes
        lastSample = all
        return hadBaseline ? rank(all, by: key) : nil
    }

    /// The top rows under `key`, with names and icons resolved for those rows only.
    private func rank(_ all: [ProcessEntry], by key: ProcessSortKey) -> [ProcessEntry] {
        let sorted = all.sorted { a, b in
            // Deterministic tie-breaks keep idle rows from shuffling between samples.
            switch key {
            case .cpu:
                if a.cpuPercent != b.cpuPercent { return a.cpuPercent > b.cpuPercent }
                if a.memoryBytes != b.memoryBytes { return a.memoryBytes > b.memoryBytes }
            case .memory:
                if a.memoryBytes != b.memoryBytes { return a.memoryBytes > b.memoryBytes }
                if a.cpuPercent != b.cpuPercent { return a.cpuPercent > b.cpuPercent }
            }
            return a.pid < b.pid
        }

        var top: [ProcessEntry] = []
        top.reserveCapacity(ProcessMonitor.rowLimit)
        for entry in sorted {
            let app = resolveAppInfo(entry.pid)
            let name = app.name ?? ProcessMonitor.processName(entry.pid)
            guard !name.isEmpty else { continue }
            top.append(ProcessEntry(id: entry.pid, name: name, memoryBytes: entry.memoryBytes,
                                    cpuPercent: entry.cpuPercent, icon: app.icon))
            if top.count == ProcessMonitor.rowLimit { break }
        }
        return top
    }

    private func resolveAppInfo(_ pid: Int32) -> (name: String?, icon: NSImage?) {
        if let cached = appInfo[pid] { return cached }
        // NSRunningApplication is documented as safe to use from any thread.
        let app = NSRunningApplication(processIdentifier: pid)
        // Some apps' localized names carry invisible bidi marks (e.g. "\u{200E}WhatsApp"); drop them.
        let name = app?.localizedName?.trimmingCharacters(in: ProcessMonitor.invisibleMarks)
        let info = (name: name.flatMap { $0.isEmpty ? nil : $0 }, icon: app?.icon)
        appInfo[pid] = info
        return info
    }

    private static let invisibleMarks = CharacterSet(charactersIn: "\u{200E}\u{200F}\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}").union(.whitespacesAndNewlines)

    private static func processName(_ pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return "" }
        return String(cString: buffer)
    }

    /// All live PIDs via sysctl(KERN_PROC_ALL). Unlike proc_listpids, this works in the App Sandbox.
    private static func allPids() -> [Int32] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        // Headroom for processes spawned between the two calls.
        size += 16 * MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [] }
        return procs.prefix(size / MemoryLayout<kinfo_proc>.stride).map { $0.kp_proc.p_pid }
    }
}

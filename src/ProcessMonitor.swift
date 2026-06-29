import Foundation
import AppKit
import SwiftUI

@_silgen_name("proc_listpids")
func proc_listpids(_ type: UInt32, _ typeinfo: UInt32, _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32

@_silgen_name("proc_pidinfo")
func proc_pidinfo(_ pid: Int32, _ flavor: Int32, _ arg: UInt64, _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32

@_silgen_name("proc_name")
func proc_name(_ pid: Int32, _ buffer: UnsafeMutablePointer<CChar>, _ buffersize: UInt32) -> Int32

struct proc_taskinfo {
    var pti_virtual_size: UInt64
    var pti_resident_size: UInt64
    var pti_total_user: UInt64
    var pti_total_system: UInt64
    var pti_threads_user: UInt64
    var pti_threads_system: UInt64
    var pti_policy: Int32
    var pti_faults: Int32
    var pti_pageins: Int32
    var pti_cow_faults: Int32
    var pti_messages_sent: Int32
    var pti_messages_received: Int32
    var pti_syscalls_mach: Int32
    var pti_syscalls_unix: Int32
    var pti_csw: Int32
    var pti_threadnum: Int32
    var pti_numrunning: Int32
    var pti_priority: Int32
}

public struct ProcessInfo: Identifiable {
    public let id = UUID()
    public let pid: Int32
    public let name: String
    public let memoryBytes: UInt64
    public let cpuPercent: Double
    public let icon: NSImage?
}

public class ProcessMonitor: ObservableObject {
    @Published public var topProcesses: [ProcessInfo] = []
    
    private var updateTimer: Timer?
    private var previousTicks: [Int32: UInt64] = [:]
    private var smoothedCpu: [Int32: Double] = [:]
    private var lastUpdateTime: Date = Date()
    private var isGhostMode = true // Start paused
    
    // Use NSCache for icons so the OS can automatically purge them if memory gets low,
    // avoiding the massive memory spikes caused by manually removing all and reloading.
    private var iconCache = NSCache<NSString, NSImage>()
    
    public init() {}
    
    public func start() {
        guard updateTimer == nil else { return }
        lastUpdateTime = Date()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
        updateStats() // Initial immediate fetch
    }
    
    public func stop() {
        updateTimer?.invalidate()
        updateTimer = nil
        previousTicks.removeAll()
        smoothedCpu.removeAll()
    }
    
    // Efficiency: Only deep-poll when not in ghost mode
    public func setGhostMode(_ enabled: Bool) {
        if enabled {
            stop()
        } else {
            start()
        }
        isGhostMode = enabled
    }
    
    private func updateStats() {
        let now = Date()
        let timeElapsed = now.timeIntervalSince(lastUpdateTime)
        lastUpdateTime = now
        
        let PROC_ALL_PIDS: UInt32 = 1
        let PROC_PIDTASKINFO: Int32 = 4
        
        let numberOfPids = proc_listpids(PROC_ALL_PIDS, 0, nil, 0)
        var pids = [Int32](repeating: 0, count: Int(numberOfPids))
        let size = pids.count * MemoryLayout<Int32>.stride
        
        _ = proc_listpids(PROC_ALL_PIDS, 0, &pids, Int32(size))
        
        var processList: [ProcessInfo] = []
        var currentTicks: [Int32: UInt64] = [:]
        var currentSmoothed: [Int32: Double] = [:]
        
        for pid in pids {
            if pid == 0 { continue }
            
            var nameBuffer = [CChar](repeating: 0, count: 256)
            _ = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let name = String(cString: nameBuffer)
            if name.isEmpty { continue }
            
            var taskInfo = proc_taskinfo(pti_virtual_size: 0, pti_resident_size: 0, pti_total_user: 0, pti_total_system: 0, pti_threads_user: 0, pti_threads_system: 0, pti_policy: 0, pti_faults: 0, pti_pageins: 0, pti_cow_faults: 0, pti_messages_sent: 0, pti_messages_received: 0, pti_syscalls_mach: 0, pti_syscalls_unix: 0, pti_csw: 0, pti_threadnum: 0, pti_numrunning: 0, pti_priority: 0)
            
            let infoSize = MemoryLayout<proc_taskinfo>.stride
            let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(infoSize))
            
            if result == infoSize {
                let totalTicks = taskInfo.pti_total_user + taskInfo.pti_total_system
                currentTicks[pid] = totalTicks
                
                var cpuPercent: Double = 0.0
                if let prevTicks = previousTicks[pid], timeElapsed > 0 {
                    let ticksDiff = Double(totalTicks) - Double(prevTicks)
                    cpuPercent = (ticksDiff / 1_000_000_000.0) / timeElapsed * 100.0
                }
                
                // Exponential Moving Average to smooth out UI sorting list
                let alpha = 0.3 // 30% new value, 70% old value
                let previousSmoothed = smoothedCpu[pid] ?? cpuPercent
                let newSmoothed = (previousSmoothed * (1.0 - alpha)) + (cpuPercent * alpha)
                currentSmoothed[pid] = newSmoothed
                
                // Do NOT fetch icon here. It wastes memory. We will fetch later for top 50 only.
                processList.append(ProcessInfo(
                    pid: pid,
                    name: name,
                    memoryBytes: taskInfo.pti_resident_size,
                    cpuPercent: max(0, newSmoothed), // Display the stable smoothed value
                    icon: nil
                ))
            }
        }
        
        previousTicks = currentTicks
        smoothedCpu = currentSmoothed
        
        // Sort by stable CPU usage
        processList.sort { $0.cpuPercent > $1.cpuPercent }
        
        // Take top 50
        var top50 = Array(processList.prefix(50))
        
        // Now fetch icons ONLY for the top 50 processes
        for i in 0..<top50.count {
            let name = top50[i].name
            if let cached = iconCache.object(forKey: name as NSString) {
                top50[i] = ProcessInfo(pid: top50[i].pid, name: name, memoryBytes: top50[i].memoryBytes, cpuPercent: top50[i].cpuPercent, icon: cached)
            } else if let newIcon = NSRunningApplication(processIdentifier: top50[i].pid)?.icon {
                iconCache.setObject(newIcon, forKey: name as NSString)
                top50[i] = ProcessInfo(pid: top50[i].pid, name: name, memoryBytes: top50[i].memoryBytes, cpuPercent: top50[i].cpuPercent, icon: newIcon)
            }
        }
        
        DispatchQueue.main.async {
            self.topProcesses = top50
        }
    }
    
    public func killProcess(pid: Int32) {
        // Send SIGKILL (9) to the process
        kill(pid, SIGKILL)
        
        // Optimistically remove it from the list for immediate UI feedback
        DispatchQueue.main.async {
            self.topProcesses.removeAll { $0.pid == pid }
        }
    }
}

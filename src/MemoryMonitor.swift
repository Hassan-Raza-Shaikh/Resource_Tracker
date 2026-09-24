import Foundation

/// The kernel's memory-pressure level — the signal behind Activity Monitor's
/// Memory Pressure graph. "Percent used" is a poor health indicator on macOS,
/// which deliberately keeps RAM full; pressure says whether it is struggling.
public enum MemoryPressure: Equatable {
    case normal, warning, critical

    public var label: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Elevated"
        case .critical: return "Critical"
        }
    }
}

public class MemoryMonitor {
    public struct MemoryInfo: Equatable {
        public let totalGB: Double
        public let activeGB: Double
        public let wiredGB: Double
        public let compressedGB: Double
        public let freeGB: Double
        public let usedGB: Double
        public let swapUsedGB: Double
        /// Percentage of installed RAM in use (app + wired + compressed).
        public let usedPercentage: Double
        public let pressure: MemoryPressure

        /// Copy with GB fields rounded to `step` GB and the percentage to 0.1, so
        /// values that render identically also compare equal (and skip a redraw).
        public func rounded(toGB step: Double) -> MemoryInfo {
            func r(_ v: Double) -> Double { (v / step).rounded() * step }
            return MemoryInfo(totalGB: r(totalGB), activeGB: r(activeGB), wiredGB: r(wiredGB),
                              compressedGB: r(compressedGB), freeGB: r(freeGB), usedGB: r(usedGB),
                              swapUsedGB: r(swapUsedGB),
                              usedPercentage: (usedPercentage * 10).rounded() / 10,
                              pressure: pressure)
        }
    }

    private var cachedInfo: MemoryInfo? = nil

    /// Installed RAM. Constant, so read once.
    private let totalBytes: Double = {
        var bytes: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &bytes, &size, nil, 0)
        return Double(bytes)
    }()

    public init() {}

    public func getMemoryInfo() -> MemoryInfo? {
        var hostSize = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vmStats = vm_statistics64_data_t()

        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(hostSize)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &hostSize)
            }
        }

        guard result == KERN_SUCCESS, totalBytes > 0 else {
            return cachedInfo
        }

        let pageSize = Double(vm_kernel_page_size)
        let active = Double(vmStats.active_count) * pageSize
        let wired = Double(vmStats.wire_count) * pageSize
        let compressed = Double(vmStats.compressor_page_count) * pageSize
        let free = Double(vmStats.free_count) * pageSize
        let inactive = Double(vmStats.inactive_count) * pageSize
        let used = active + wired + compressed

        let gb = 1024.0 * 1024.0 * 1024.0
        let newInfo = MemoryInfo(
            totalGB: totalBytes / gb,
            activeGB: active / gb,
            wiredGB: wired / gb,
            compressedGB: compressed / gb,
            freeGB: (free + inactive) / gb,
            usedGB: used / gb,
            swapUsedGB: MemoryMonitor.swapUsedBytes() / gb,
            usedPercentage: used / totalBytes * 100.0,
            pressure: MemoryMonitor.pressure()
        )
        cachedInfo = newInfo
        return newInfo
    }

    private static func pressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        switch level {
        case 4: return .critical   // DISPATCH_MEMORYPRESSURE_CRITICAL
        case 2: return .warning    // DISPATCH_MEMORYPRESSURE_WARN
        default: return .normal
        }
    }

    private static func swapUsedBytes() -> Double {
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 else { return 0 }
        return Double(swap.xsu_used)
    }
}

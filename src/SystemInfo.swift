import Foundation
import Metal

/// Static facts about this Mac, read once.
enum SystemInfo {
    /// e.g. "Apple M1 Pro". Empty if unavailable.
    static let cpuModel: String = sysctlString("machdep.cpu.brand_string")

    /// e.g. "Apple M1 Pro". Empty if there is no Metal device.
    static let gpuModel: String = MTLCreateSystemDefaultDevice()?.name ?? ""

    /// Kernel boot time. Constant while the app runs.
    static let bootDate: Date = {
        var mib = [CTL_KERN, KERN_BOOTTIME]
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.stride
        if sysctl(&mib, 2, &bootTime, &size, nil, 0) == 0, bootTime.tv_sec != 0 {
            return Date(timeIntervalSince1970: Double(bootTime.tv_sec))
        }
        return Date()
    }()

    /// Multiplier from Mach absolute-time ticks to nanoseconds: 1 on Intel,
    /// 125/3 on Apple Silicon. proc_taskinfo CPU times are reported in ticks.
    static let nanosecondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info.denom == 0 ? 1 : Double(info.numer) / Double(info.denom)
    }()

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }
}

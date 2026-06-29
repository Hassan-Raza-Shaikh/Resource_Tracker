import Foundation

public class MemoryMonitor {
    public struct MemoryInfo {
        public let totalGB: Double
        public let activeGB: Double
        public let wiredGB: Double
        public let compressedGB: Double
        public let freeGB: Double
        public let usedGB: Double
        public let pressurePercentage: Double
    }
    
    public init() {}
    
    public func getMemoryInfo() -> MemoryInfo? {
        var hostSize = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vmStats = vm_statistics64_data_t()
        
        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(hostSize)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &hostSize)
            }
        }
        
        guard result == KERN_SUCCESS else { return nil }
        
        var totalBytes: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &totalBytes, &size, nil, 0)
        
        let pageSize = vm_kernel_page_size
        
        let active = Double(vmStats.active_count) * Double(pageSize)
        let wired = Double(vmStats.wire_count) * Double(pageSize)
        let compressed = Double(vmStats.compressor_page_count) * Double(pageSize)
        let free = Double(vmStats.free_count) * Double(pageSize)
        let inactive = Double(vmStats.inactive_count) * Double(pageSize)
        
        let used = active + wired + compressed
        let total = Double(totalBytes)
        let pressure = (used / total) * 100.0
        
        let gb = 1024.0 * 1024.0 * 1024.0
        return MemoryInfo(
            totalGB: total / gb,
            activeGB: active / gb,
            wiredGB: wired / gb,
            compressedGB: compressed / gb,
            freeGB: (free + inactive) / gb,
            usedGB: used / gb,
            pressurePercentage: pressure
        )
    }
}

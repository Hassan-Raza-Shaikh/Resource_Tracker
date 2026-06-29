import Foundation
import MachO

public class CPUMonitor {
    private var prevCpuInfo: [Int32] = []
    
    public init() {}
    
    public func getCPUUsages() -> [Double] {
        var processorInfo: processor_info_array_t?
        var processorMsgCount: mach_msg_type_number_t = 0
        var processorCount: mach_msg_type_number_t = 0
        
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorMsgCount
        )
        
        guard result == KERN_SUCCESS, let info = processorInfo else {
            return []
        }
        
        let cpuInfo = info.withMemoryRebound(to: Int32.self, capacity: Int(processorMsgCount)) { pointer in
            Array(UnsafeBufferPointer(start: pointer, count: Int(processorMsgCount)))
        }
        
        let size = vm_size_t(processorMsgCount) * vm_size_t(MemoryLayout<Int32>.size)
        vm_deallocate(mach_task_self_, vm_address_t(Int(bitPattern: info)), size)
        
        if prevCpuInfo.isEmpty {
            prevCpuInfo = cpuInfo
            return Array(repeating: 0.0, count: Int(processorCount))
        }
        
        var usages: [Double] = []
        for i in 0..<Int(processorCount) {
            let offset = i * Int(CPU_STATE_MAX)
            
            let user = cpuInfo[offset + Int(CPU_STATE_USER)]
            let system = cpuInfo[offset + Int(CPU_STATE_SYSTEM)]
            let idle = cpuInfo[offset + Int(CPU_STATE_IDLE)]
            let nice = cpuInfo[offset + Int(CPU_STATE_NICE)]
            
            let prevUser = prevCpuInfo[offset + Int(CPU_STATE_USER)]
            let prevSystem = prevCpuInfo[offset + Int(CPU_STATE_SYSTEM)]
            let prevIdle = prevCpuInfo[offset + Int(CPU_STATE_IDLE)]
            let prevNice = prevCpuInfo[offset + Int(CPU_STATE_NICE)]
            
            let activeDiff = Double((user - prevUser) + (system - prevSystem) + (nice - prevNice))
            let totalDiff = activeDiff + Double(idle - prevIdle)
            
            let usage = totalDiff > 0 ? (activeDiff / totalDiff) * 100.0 : 0.0
            usages.append(usage)
        }
        
        prevCpuInfo = cpuInfo
        return usages
    }
}

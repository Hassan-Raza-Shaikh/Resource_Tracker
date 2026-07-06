import Foundation
import IOKit

public class GPUMonitor: ObservableObject {
    @Published public var utilization: Double = 0.0
    private var lastCheckTime = Date(timeIntervalSince1970: 0)
    
    public init() {}
    
    public func start() {} // No longer needed
    public func stop() {} // No longer needed
    
    public func getGPUUtilization() -> Double {
        let now = Date()
        let timeInterval = now.timeIntervalSince(lastCheckTime)
        
        if timeInterval < 1.0 {
            return utilization
        }
        
        let matchDict = IOServiceMatching("IOAccelerator")
        var iterator: io_iterator_t = 0
        
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &iterator) == KERN_SUCCESS else {
            return utilization
        }
        
        var service = IOIteratorNext(iterator)
        while service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS {
                if let dict = props?.takeRetainedValue() as? [String: Any],
                   let perf = dict["PerformanceStatistics"] as? [String: Any],
                   let util = perf["Device Utilization %"] as? Int {
                    
                    self.utilization = Double(util)
                    IOObjectRelease(service)
                    break
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        
        // Drain any remaining services in the iterator to prevent IOKit object leaks
        while service != 0 {
            service = IOIteratorNext(iterator)
            if service != 0 { IOObjectRelease(service) }
        }
        
        IOObjectRelease(iterator)
        lastCheckTime = now
        return utilization
    }
}

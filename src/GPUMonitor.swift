import Foundation
import IOKit

/// GPU utilisation from the accelerator's IORegistry "PerformanceStatistics".
public class GPUMonitor {
    public init() {}

    /// Device utilisation in percent; the busiest GPU if there is more than one.
    public func getGPUUtilization() -> Double {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }

        var busiest = 0.0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            // Fetch just this one property rather than the accelerator's whole table.
            if let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
               let utilization = (stats["Device Utilization %"] as? NSNumber)?.doubleValue {
                busiest = max(busiest, utilization)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return busiest
    }
}

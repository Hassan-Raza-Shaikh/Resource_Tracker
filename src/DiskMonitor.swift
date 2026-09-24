import Foundation
import IOKit
import IOKit.storage

/// Capacity of the startup volume.
public struct DiskSpace: Equatable {
    public let volumeName: String
    public let totalBytes: Int64
    /// Matches Finder's "Available": includes purgeable space the system can reclaim.
    public let availableBytes: Int64

    public var usedBytes: Int64 { max(totalBytes - availableBytes, 0) }
    public var usedFraction: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0 }
}

public class DiskMonitor {
    private var previous: (read: UInt64, write: UInt64)?
    private var lastCheckTime: Date?

    public init() {}

    /// Bytes/second read and written across all block-storage devices since the previous call.
    public func getDiskRates() -> (readBytesPerSec: Double, writeBytesPerSec: Double) {
        let current = DiskMonitor.cumulativeBytes()
        let now = Date()
        defer { previous = current; lastCheckTime = now }
        guard let prev = previous, let last = lastCheckTime else { return (0, 0) }
        let elapsed = now.timeIntervalSince(last)
        guard elapsed > 0 else { return (0, 0) }
        // Totals only go backwards when a device is ejected; treat that interval as idle.
        let read = current.read >= prev.read ? current.read - prev.read : 0
        let write = current.write >= prev.write ? current.write - prev.write : 0
        return (Double(read) / elapsed, Double(write) / elapsed)
    }

    public func getDiskSpaceInfo() -> DiskSpace? {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return DiskSpace(volumeName: values.volumeName ?? "Startup Disk",
                         totalBytes: Int64(total),
                         availableBytes: available)
    }

    /// Lifetime bytes read/written, summed over every IOBlockStorageDriver (what iostat reads).
    private static func cumulativeBytes() -> (read: UInt64, write: UInt64) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOBlockStorageDriverClass), &iterator) == KERN_SUCCESS else {
            return (0, 0)
        }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0, write: UInt64 = 0
        var driver = IOIteratorNext(iterator)
        while driver != 0 {
            // Fetch just the Statistics dictionary, not the driver's whole property table.
            if let stats = IORegistryEntryCreateCFProperty(driver, kIOBlockStorageDriverStatisticsKey as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                read += (stats[kIOBlockStorageDriverStatisticsBytesReadKey] as? NSNumber)?.uint64Value ?? 0
                write += (stats[kIOBlockStorageDriverStatisticsBytesWrittenKey] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(driver)
            driver = IOIteratorNext(iterator)
        }
        return (read, write)
    }
}

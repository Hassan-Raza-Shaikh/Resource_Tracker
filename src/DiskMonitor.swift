import Foundation
import IOKit
import IOKit.storage

public class DiskMonitor {
    private var prevReadBytes: UInt64 = 0
    private var prevWriteBytes: UInt64 = 0
    private var lastCheckTime = Date()
    
    public init() {}
    
    public func getDiskRates() -> (readBytesPerSec: Double, writeBytesPerSec: Double) {
        var readBytes: UInt64 = 0
        var writeBytes: UInt64 = 0
        
        let masterPort = kIOMainPortDefault
        let matchingDict = IOServiceMatching(kIOMediaClass)
        
        var iterator: io_iterator_t = 0
        let kernResult = IOServiceGetMatchingServices(masterPort, matchingDict, &iterator)
        
        if kernResult == KERN_SUCCESS {
            var drive: io_registry_entry_t = IOIteratorNext(iterator)
            while drive != 0 {
                var parent: io_registry_entry_t = 0
                let parentResult = IORegistryEntryGetParentEntry(drive, kIOServicePlane, &parent)
                
                if parentResult == KERN_SUCCESS {
                    if IOObjectConformsTo(parent, kIOBlockStorageDriverClass) != 0 {
                        var properties: Unmanaged<CFMutableDictionary>? = nil
                        let propertiesResult = IORegistryEntryCreateCFProperties(parent, &properties, kCFAllocatorDefault, 0)
                        
                        if propertiesResult == KERN_SUCCESS, let propertiesDict = properties?.takeRetainedValue() as? [String: Any] {
                            if let statistics = propertiesDict[kIOBlockStorageDriverStatisticsKey] as? [String: Any] {
                                if let reads = statistics[kIOBlockStorageDriverStatisticsBytesReadKey] as? NSNumber {
                                    readBytes += reads.uint64Value
                                }
                                if let writes = statistics[kIOBlockStorageDriverStatisticsBytesWrittenKey] as? NSNumber {
                                    writeBytes += writes.uint64Value
                                }
                            }
                        }
                    }
                    IOObjectRelease(parent)
                }
                IOObjectRelease(drive)
                drive = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }
        
        let now = Date()
        let timeInterval = now.timeIntervalSince(lastCheckTime)
        lastCheckTime = now
        
        if prevReadBytes == 0 && prevWriteBytes == 0 {
            prevReadBytes = readBytes
            prevWriteBytes = writeBytes
            return (0, 0)
        }
        
        let diffRead = readBytes >= prevReadBytes ? readBytes - prevReadBytes : 0
        let diffWrite = writeBytes >= prevWriteBytes ? writeBytes - prevWriteBytes : 0
        
        prevReadBytes = readBytes
        prevWriteBytes = writeBytes
        
        guard timeInterval > 0 else { return (0, 0) }
        return (Double(diffRead) / timeInterval, Double(diffWrite) / timeInterval)
    }
    
    public func getDiskSpaceInfo() -> (totalGB: Double, freeGB: Double, usedGB: Double)? {
        let fileManager = FileManager.default
        do {
            let values = try fileManager.attributesOfFileSystem(forPath: "/")
            if let totalSize = values[.systemSize] as? NSNumber,
               let freeSize = values[.systemFreeSize] as? NSNumber {
                let totalBytes = totalSize.doubleValue
                let freeBytes = freeSize.doubleValue
                let usedBytes = totalBytes - freeBytes
                
                let gb = 1024.0 * 1024.0 * 1024.0
                return (totalBytes / gb, freeBytes / gb, usedBytes / gb)
            }
        } catch {
            print("Error reading disk space: \(error)")
        }
        return nil
    }
}

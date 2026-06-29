import Foundation
import SystemConfiguration

public class NetworkMonitor {
    private var prevBytesIn: UInt64 = 0
    private var prevBytesOut: UInt64 = 0
    private var lastCheckTime = Date()
    
    public init() {}
    
    private var cachedRates: (Double, Double) = (0.0, 0.0)
    
    public func getNetworkRates() -> (bytesInPerSec: Double, bytesOutPerSec: Double) {
        let now = Date()
        let timeInterval = now.timeIntervalSince(lastCheckTime)
        
        // OS networking stats generally don't update sub-second.
        // Return cached rates for high-frequency chart polling to keep graphs smooth.
        if timeInterval < 1.0 && prevBytesIn != 0 {
            return cachedRates
        }
        
        var interfaceAddresses: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&interfaceAddresses) == 0, let firstAddress = interfaceAddresses else {
            return (0, 0)
        }
        
        var totalBytesIn: UInt64 = 0
        var totalBytesOut: UInt64 = 0
        
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while pointer != nil {
            defer { pointer = pointer?.pointee.ifa_next }
            
            guard let interface = pointer?.pointee else { continue }
            
            if interface.ifa_addr.pointee.sa_family == UInt8(AF_LINK) {
                if let data = interface.ifa_data {
                    let networkData = data.assumingMemoryBound(to: if_data.self)
                    totalBytesIn += UInt64(networkData.pointee.ifi_ibytes)
                    totalBytesOut += UInt64(networkData.pointee.ifi_obytes)
                }
            }
        }
        freeifaddrs(interfaceAddresses)
        
        lastCheckTime = now
        
        if prevBytesIn == 0 && prevBytesOut == 0 {
            prevBytesIn = totalBytesIn
            prevBytesOut = totalBytesOut
            return (0, 0)
        }
        
        let diffIn = totalBytesIn >= prevBytesIn ? totalBytesIn - prevBytesIn : 0
        let diffOut = totalBytesOut >= prevBytesOut ? totalBytesOut - prevBytesOut : 0
        
        prevBytesIn = totalBytesIn
        prevBytesOut = totalBytesOut
        
        guard timeInterval > 0 else { return (0, 0) }
        cachedRates = (Double(diffIn) / timeInterval, Double(diffOut) / timeInterval)
        return cachedRates
    }
}

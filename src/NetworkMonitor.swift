import Foundation

public class NetworkMonitor {
    /// Per-interface byte counters from the previous sample. The kernel's if_data
    /// counters are 32-bit and wrap every 4 GB, so deltas are taken per interface
    /// rather than on a running total (where one wrap would zero the whole tick).
    private var previous: [String: (rx: UInt32, tx: UInt32)] = [:]
    private var lastCheckTime: Date?

    /// Interfaces whose traffic is local (loopback) or already counted on a physical
    /// interface (VPN / IPsec tunnels, gif / stf encapsulation).
    private static let excludedPrefixes = ["lo", "utun", "ipsec", "gif", "stf"]

    public init() {}

    /// Bytes/second received and sent since the previous call.
    public func getNetworkRates() -> (bytesInPerSec: Double, bytesOutPerSec: Double) {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return (0, 0) }
        defer { freeifaddrs(head) }

        var current: [String: (rx: UInt32, tx: UInt32)] = [:]
        var cursor = head
        while let entry = cursor?.pointee {
            cursor = entry.ifa_next
            guard let addr = entry.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = entry.ifa_data else { continue }
            let name = String(cString: entry.ifa_name)
            if NetworkMonitor.excludedPrefixes.contains(where: { name.hasPrefix($0) }) { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            current[name] = (stats.ifi_ibytes, stats.ifi_obytes)
        }

        let now = Date()
        defer { previous = current; lastCheckTime = now }
        guard let last = lastCheckTime else { return (0, 0) }
        let elapsed = now.timeIntervalSince(last)
        guard elapsed > 0 else { return (0, 0) }

        var rx: UInt64 = 0, tx: UInt64 = 0
        for (name, counters) in current {
            guard let prev = previous[name] else { continue }  // new interface: no baseline yet
            rx += NetworkMonitor.delta(counters.rx, prev.rx)
            tx += NetworkMonitor.delta(counters.tx, prev.tx)
        }
        return (Double(rx) / elapsed, Double(tx) / elapsed)
    }

    static func delta(_ current: UInt32, _ previous: UInt32) -> UInt64 {
        if current >= previous { return UInt64(current - previous) }
        // Went backwards. A genuine 32-bit wrap only happens from near the top of the
        // range; otherwise the counter was reset (interface bounced), so count from 0.
        return previous > UInt32.max / 2 ? UInt64(current &- previous) : UInt64(current)
    }
}

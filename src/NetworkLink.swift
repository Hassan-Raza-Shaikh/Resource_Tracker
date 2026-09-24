import Foundation
import Network
import CoreWLAN

/// The connection this Mac is using right now, and how fast its local link is.
///
/// The local link rate is the ceiling for any speed test: a result close to it means the
/// Wi-Fi or Ethernet link is the bottleneck, one far below it means the limit is further out.
struct NetworkLink: Equatable {
    enum Kind: Equatable { case ethernet, wifi, cellular, other }

    var kind: Kind
    var interfaceName: String
    /// Negotiated link rate in Mbps (Ethernet) or current transmit rate (Wi-Fi).
    var linkMbps: Double?
    var wifiStandard: String?
    var wifiBand: String?
    var wifiSignal: String?
    /// Personal Hotspot or cellular.
    var isExpensive: Bool
    /// Low Data Mode is on.
    var isConstrained: Bool
    var usesVPN: Bool

    var kindLabel: String {
        switch kind {
        case .ethernet: return "Ethernet"
        case .wifi: return "Wi-Fi"
        case .cellular: return "Cellular"
        case .other: return usesVPN ? "VPN" : "Network"
        }
    }

    /// e.g. "Ethernet · 1 Gbps link" or "Wi-Fi 6 · 5 GHz · 866 Mbps · Excellent signal".
    var summary: String {
        var parts = [kind == .wifi ? (wifiStandard ?? "Wi-Fi") : kindLabel]
        if let wifiBand { parts.append(wifiBand) }
        if let linkMbps { parts.append(kind == .ethernet ? "\(Self.rate(linkMbps)) link" : Self.rate(linkMbps)) }
        if let wifiSignal { parts.append("\(wifiSignal) signal") }
        return parts.joined(separator: " · ")
    }

    static func rate(_ mbps: Double) -> String {
        mbps >= 1000 ? String(format: mbps.truncatingRemainder(dividingBy: 1000) == 0 ? "%.0f Gbps" : "%.1f Gbps", mbps / 1000)
                     : String(format: "%.0f Mbps", mbps)
    }

    init(kind: Kind, interfaceName: String, linkMbps: Double?, wifiStandard: String? = nil, wifiBand: String? = nil,
         wifiSignal: String? = nil, isExpensive: Bool, isConstrained: Bool, usesVPN: Bool) {
        self.kind = kind
        self.interfaceName = interfaceName
        self.linkMbps = linkMbps
        self.wifiStandard = wifiStandard
        self.wifiBand = wifiBand
        self.wifiSignal = wifiSignal
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
        self.usesVPN = usesVPN
    }

    /// Reads the current path once.
    static func current() async -> NetworkLink? {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let once = OnceFlag()
            monitor.pathUpdateHandler = { path in
                guard once.claim() else { return }
                monitor.cancel()
                continuation.resume(returning: NetworkLink(path: path))
            }
            monitor.start(queue: DispatchQueue(label: "com.hassan.ResourceTracker.path"))
        }
    }

    private init?(path: NWPath) {
        guard path.status == .satisfied, let primary = path.availableInterfaces.first else { return nil }
        interfaceName = primary.name
        isExpensive = path.isExpensive
        isConstrained = path.isConstrained
        usesVPN = primary.type == .other && ["utun", "ipsec", "ppp"].contains { primary.name.hasPrefix($0) }

        switch primary.type {
        case .wiredEthernet:
            kind = .ethernet
            linkMbps = Self.baudRateMbps(of: primary.name)
        case .wifi:
            kind = .wifi
            if let wifi = CWWiFiClient.shared().interface(withName: primary.name) ?? CWWiFiClient.shared().interface() {
                let tx = wifi.transmitRate()
                linkMbps = tx > 0 ? tx : nil
                wifiStandard = Self.standard(wifi.activePHYMode())
                wifiBand = Self.band(wifi.wlanChannel()?.channelBand)
                wifiSignal = Self.signal(rssi: wifi.rssiValue())
            }
        case .cellular:
            kind = .cellular
        default:
            kind = .other
        }
    }

    private static func baudRateMbps(of name: String) -> Double? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return nil }
        defer { freeifaddrs(head) }
        var cursor = head
        while let entry = cursor?.pointee {
            cursor = entry.ifa_next
            guard String(cString: entry.ifa_name) == name, let addr = entry.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK), let data = entry.ifa_data else { continue }
            let baud = data.assumingMemoryBound(to: if_data.self).pointee.ifi_baudrate
            return baud > 0 ? Double(baud) / 1_000_000 : nil
        }
        return nil
    }

    private static func standard(_ mode: CWPHYMode) -> String? {
        switch mode.rawValue {
        case 4: return "Wi-Fi 4"      // 802.11n
        case 5: return "Wi-Fi 5"      // 802.11ac
        case 6: return "Wi-Fi 6"      // 802.11ax
        case 7: return "Wi-Fi 7"      // 802.11be
        case 1, 2, 3: return "Wi-Fi"  // 802.11a/b/g
        default: return nil
        }
    }

    private static func band(_ band: CWChannelBand?) -> String? {
        switch band?.rawValue {
        case 1: return "2.4 GHz"
        case 2: return "5 GHz"
        case 3: return "6 GHz"
        default: return nil
        }
    }

    private static func signal(rssi: Int) -> String? {
        guard rssi < 0 else { return nil }
        if rssi >= -55 { return "Excellent" }
        if rssi >= -67 { return "Good" }
        if rssi >= -75 { return "Fair" }
        return "Weak"
    }
}

/// Lets exactly one caller through — for resuming a continuation from a callback that may fire repeatedly.
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.withLock {
            if claimed { return false }
            claimed = true
            return true
        }
    }
}

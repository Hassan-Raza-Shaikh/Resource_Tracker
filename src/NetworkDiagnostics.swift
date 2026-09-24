import Foundation
import Network
import SystemConfiguration
import Security
import Observation

/// Looks for restrictions and quirks on the current network. Every check is independent and
/// runs concurrently; rows fill in as each one finishes.
@MainActor
@Observable
final class NetworkDiagnostics {
    enum Status: Equatable { case pending, ok, warning, blocked, info }

    enum Group: String, CaseIterable {
        case access = "Access", dns = "DNS", traffic = "Traffic", ports = "Ports"
    }

    enum ID: String, CaseIterable {
        case internet, lowDataMode, vpnProxy, publicAddress, ipv6
        case dnsServers, dnsHijack, encryptedDNS
        case httpsInspection, http3, udp
        case ssh, mailRelay, mailSubmission, imap, applePush

        var title: String {
            switch self {
            case .internet: return "Internet access"
            case .lowDataMode: return "Low Data Mode"
            case .vpnProxy: return "VPN & proxy"
            case .publicAddress: return "Public IP address"
            case .ipv6: return "IPv6"
            case .dnsServers: return "DNS servers"
            case .dnsHijack: return "Mistyped addresses"
            case .encryptedDNS: return "Encrypted DNS (DNS-over-TLS)"
            case .httpsInspection: return "HTTPS inspection"
            case .http3: return "HTTP/3 (QUIC)"
            case .udp: return "UDP (calls & games)"
            case .ssh: return "SSH · port 22"
            case .mailRelay: return "Direct mail · port 25"
            case .mailSubmission: return "Sending mail · port 587"
            case .imap: return "Receiving mail · port 993"
            case .applePush: return "Apple Push · port 5223"
            }
        }

        var group: Group {
            switch self {
            case .internet, .lowDataMode, .vpnProxy, .publicAddress, .ipv6: return .access
            case .dnsServers, .dnsHijack, .encryptedDNS: return .dns
            case .httpsInspection, .http3, .udp: return .traffic
            case .ssh, .mailRelay, .mailSubmission, .imap, .applePush: return .ports
            }
        }
    }

    struct Check: Identifiable, Equatable {
        let id: ID
        var status: Status = .pending
        var value = "Checking…"
        /// What the result means for you. Shown for anything that isn't simply fine.
        var note: String?
    }

    private(set) var checks: [Check] = []
    private(set) var isRunning = false
    private(set) var finishedAt: Date?

    /// Warnings and blocks, for the summary line.
    var issues: [Check] { checks.filter { $0.status == .warning || $0.status == .blocked } }

    func run() {
        guard !isRunning else { return }
        isRunning = true
        finishedAt = nil
        checks = ID.allCases.map { Check(id: $0) }
        Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.checkInternet() }
                group.addTask { await self.checkConnection() }
                group.addTask { await self.checkDNS() }
                group.addTask { await self.checkEncryptedDNS() }
                group.addTask { await self.checkHTTPSInspection() }
                group.addTask { await self.checkHTTP3() }
                group.addTask { await self.checkUDPAndAddress() }
                group.addTask { await self.checkIPv6() }
                group.addTask { await self.checkPorts() }
            }
            isRunning = false
            finishedAt = Date()
        }
    }

    private func set(_ id: ID, _ status: Status, _ value: String, note: String? = nil) {
        guard let index = checks.firstIndex(where: { $0.id == id }) else { return }
        checks[index].status = status
        checks[index].value = value
        checks[index].note = note
    }

    // MARK: Checks

    private func checkInternet() async {
        switch await Probes.captivePortal() {
        case .connected:
            set(.internet, .ok, "Connected")
        case .intercepted:
            set(.internet, .blocked, "Sign-in required",
                note: "A captive portal is intercepting web traffic. Open a browser page to sign in to this network.")
        case .offline:
            set(.internet, .blocked, "No internet access",
                note: "This Mac is on a network, but it can’t reach the internet.")
        }
    }

    private func checkConnection() async {
        let link = await NetworkLink.current()
        switch (link?.isConstrained, link?.isExpensive) {
        case (true?, _):
            set(.lowDataMode, .warning, "On",
                note: "macOS asks apps to hold back background data, so some updates, backups, and syncing pause.")
        case (_, true?):
            set(.lowDataMode, .info, "Off · metered connection",
                note: "macOS treats this as a costly connection (Personal Hotspot or cellular).")
        default:
            set(.lowDataMode, .ok, "Off")
        }

        if let proxy = Probes.proxySummary() {
            set(.vpnProxy, .warning, proxy, note: "Web traffic is routed through a proxy, which can see and filter it.")
        } else if link?.usesVPN == true {
            set(.vpnProxy, .info, "VPN active (\(link?.interfaceName ?? "tunnel"))",
                note: "Speed tests and checks measure the VPN’s route, not your local network’s.")
        } else {
            set(.vpnProxy, .ok, "Not in use")
        }
    }

    private func checkDNS() async {
        let servers = Probes.dnsServers()
        // A random name under example.com must not exist, so a correct resolver says so; it also
        // can't be cached, so the time is a full lookup.
        let lookup = await Probes.resolve("rt-\(UUID().uuidString.prefix(8).lowercased()).example.com")
        let time = "\(Int(lookup.ms.rounded())) ms lookups"
        let serverList = servers.isEmpty ? "Automatic" : servers.prefix(3).joined(separator: ", ")
        if lookup.failed {
            set(.dnsServers, .blocked, serverList, note: "DNS isn’t answering, so names like apple.com can’t be looked up.")
        } else if lookup.ms > 150 {
            set(.dnsServers, .warning, "\(serverList) · \(time)",
                note: "Slow lookups add a delay to every new site you visit.")
        } else {
            set(.dnsServers, .info, "\(serverList) · \(time)")
        }

        if lookup.failed {
            set(.dnsHijack, .info, "Couldn’t test")
        } else if lookup.addresses.isEmpty {
            set(.dnsHijack, .ok, "Handled correctly")
        } else {
            set(.dnsHijack, .warning, "Redirected",
                note: "Your network answers for sites that don’t exist (NXDOMAIN hijacking), usually to show ads or a search page instead of an error.")
        }
    }

    private func checkEncryptedDNS() async {
        switch await Probes.tcpConnect(host: "1.1.1.1", port: 853) {
        case .open:
            set(.encryptedDNS, .ok, "Allowed")
        case .refused, .noResponse:
            set(.encryptedDNS, .blocked, "Blocked",
                note: "Private DNS over TLS (e.g. Cloudflare’s 1.1.1.1) can’t be used here; lookups go through the network’s own DNS.")
        case .unavailable(let reason):
            set(.encryptedDNS, .info, "Couldn’t test", note: reason)
        }
    }

    private func checkHTTPSInspection() async {
        // Inspecting proxies often exempt Apple's own domains, so test ordinary sites.
        let roots = await withTaskGroup(of: Probes.TrustRoot?.self) { group in
            for site in ["https://www.wikipedia.org", "https://speed.cloudflare.com/__down?bytes=0"] {
                group.addTask { await Probes.trustRoot(of: URL(string: site)!) }
            }
            return await group.reduce(into: [Probes.TrustRoot]()) { if let r = $1 { $0.append(r) } }
        }
        if roots.isEmpty {
            set(.httpsInspection, .info, "Couldn’t test")
        } else if let custom = roots.first(where: { !$0.isBuiltIn }) {
            set(.httpsInspection, .warning, "Detected: “\(custom.name)”",
                note: "A certificate authority installed on this Mac or network can decrypt your HTTPS traffic. Common on work and school networks.")
        } else {
            set(.httpsInspection, .ok, "None")
        }
    }

    private func checkHTTP3() async {
        if await Probes.negotiatesHTTP3() {
            set(.http3, .ok, "Works")
        } else {
            set(.http3, .warning, "Unavailable",
                note: "UDP port 443 looks blocked, so sites fall back to HTTP/2, which is slower to connect on busy or lossy networks.")
        }
    }

    private func checkUDPAndAddress() async {
        async let stun = Probes.stunMappedAddress()
        async let traceA = Probes.traceIP()
        async let traceB = Probes.traceIP()
        let viaUDP = await stun
        let addresses = Array(Set([viaUDP, await traceA, await traceB].compactMap { $0 })).sorted()

        if viaUDP != nil {
            set(.udp, .ok, "Works")
        } else {
            set(.udp, .blocked, "Blocked",
                note: "Video calls and online games have to fall back to slower relays or TCP.")
        }

        switch addresses.count {
        case 0:
            set(.publicAddress, .info, "Unknown")
        case 1:
            set(.publicAddress, .info, addresses[0])
        default:
            set(.publicAddress, .info, "\(addresses.count) different addresses",
                note: "Your traffic leaves through more than one public address (\(addresses.joined(separator: ", "))), which is typical of large or multi-provider networks. Sites that tie a login to one address may occasionally sign you out.")
        }
    }

    private func checkIPv6() async {
        if case .open = await Probes.tcpConnect(host: "2606:4700:4700::1111", port: 443) {
            set(.ipv6, .ok, "Available")
        } else {
            set(.ipv6, .info, "Not available", note: "Common and harmless: everything still works over IPv4.")
        }
    }

    private func checkPorts() async {
        let targets: [(ID, String, UInt16, String)] = [
            (.ssh, "github.com", 22, "Git and remote logins over SSH won’t work."),
            (.mailRelay, "gmail-smtp-in.l.google.com", 25,
             "Mail servers can’t be reached directly. Providers often block this to stop spam; mail apps use port 587 instead, so normal email is unaffected."),
            (.mailSubmission, "smtp.gmail.com", 587, "Mail apps may be unable to send email."),
            (.imap, "imap.gmail.com", 993, "Mail apps may be unable to receive email."),
            (.applePush, "courier.push.apple.com", 5223,
             "Apple push notifications fall back to port 443, so they still arrive, sometimes more slowly."),
        ]
        await withTaskGroup(of: Void.self) { group in
            for (id, host, port, consequence) in targets {
                group.addTask {
                    let result = await Probes.tcpConnect(host: host, port: port)
                    await MainActor.run {
                        switch result {
                        case .open: self.set(id, .ok, "Open")
                        case .refused: self.set(id, .blocked, "Blocked", note: "The connection was actively refused. \(consequence)")
                        case .noResponse: self.set(id, .blocked, "Blocked", note: "No response; the traffic appears to be dropped. \(consequence)")
                        case .unavailable(let reason): self.set(id, .info, "Couldn’t test", note: reason)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Probes

/// The individual network measurements, each self-contained and safe to call from any thread.
enum Probes {
    enum CaptiveResult { case connected, intercepted, offline }

    /// Apple's own connectivity check: a plain-HTTP page that says "Success". A captive portal
    /// answers with its sign-in page (or a redirect) instead.
    static func captivePortal() async -> CaptiveResult {
        var request = URLRequest(url: URL(string: "http://captive.apple.com/hotspot-detect.html")!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 6
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, response) = try await session.data(for: request, delegate: NoRedirects())
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
                && String(decoding: data, as: UTF8.self).contains("<TITLE>Success</TITLE>")
            return ok ? .connected : .intercepted
        } catch {
            return .offline
        }
    }

    enum PortResult: Equatable {
        case open(ms: Int)
        case refused
        case noResponse
        case unavailable(String)
    }

    /// A bare TCP connect (nothing is sent), distinguishing an active refusal from silence.
    static func tcpConnect(host: String, port: UInt16, timeout: TimeInterval = 4) async -> PortResult {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
            let once = OnceFlag()
            let start = Date()
            let finish = { (result: PortResult) in
                guard once.claim() else { return }
                connection.cancel()
                continuation.resume(returning: result)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(.open(ms: Int(Date().timeIntervalSince(start) * 1000)))
                case .waiting(let error), .failed(let error):
                    switch error {
                    case .posix(.ECONNREFUSED): finish(.refused)
                    case .posix(.ENETDOWN), .posix(.ENETUNREACH), .posix(.EHOSTUNREACH):
                        finish(.unavailable("No route to \(host)."))
                    case .dns: finish(.unavailable("Couldn’t look up \(host)."))
                    default: if case .failed = state { finish(.noResponse) }
                    }
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(.noResponse) }
        }
    }

    static func dnsServers() -> [String] {
        guard let store = SCDynamicStoreCreate(nil, "ResourceTracker" as CFString, nil, nil),
              let dns = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any] else { return [] }
        return dns["ServerAddresses"] as? [String] ?? []
    }

    /// Looks a name up with the system resolver, timing it.
    static func resolve(_ host: String) async -> (addresses: [String], ms: Double, failed: Bool) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var hints = addrinfo()
                hints.ai_socktype = SOCK_STREAM
                var results: UnsafeMutablePointer<addrinfo>?
                let start = Date()
                let status = getaddrinfo(host, nil, &hints, &results)
                let ms = Date().timeIntervalSince(start) * 1000
                var addresses: [String] = []
                var cursor = results
                while let info = cursor?.pointee {
                    var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(info.ai_addr, info.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                        addresses.append(String(cString: buffer))
                    }
                    cursor = info.ai_next
                }
                if results != nil { freeaddrinfo(results) }
                // "No such name" is the correct answer here; anything else non-zero means DNS itself failed.
                let failed = status != 0 && status != EAI_NONAME && status != EAI_NODATA
                continuation.resume(returning: (addresses, ms, failed))
            }
        }
    }

    static func proxySummary() -> String? {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else { return nil }
        func enabled(_ key: String) -> Bool { (settings[key] as? NSNumber)?.boolValue == true }
        if enabled("ProxyAutoConfigEnable") { return "Automatic proxy (PAC)" }
        if enabled("HTTPSEnable"), let host = settings["HTTPSProxy"] as? String { return "HTTPS proxy \(host)" }
        if enabled("HTTPEnable"), let host = settings["HTTPProxy"] as? String { return "HTTP proxy \(host)" }
        if enabled("SOCKSEnable"), let host = settings["SOCKSProxy"] as? String { return "SOCKS proxy \(host)" }
        return nil
    }

    struct TrustRoot: Sendable {
        let name: String
        let isBuiltIn: Bool
    }

    /// The root certificate a site's HTTPS connection chains to, and whether it's one of the
    /// CAs built into macOS. An inspecting proxy re-signs traffic with its own root instead.
    static func trustRoot(of url: URL) async -> TrustRoot? {
        let recorder = TrustRecorder()
        let session = URLSession(configuration: .ephemeral, delegate: recorder, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8
        _ = try? await session.data(for: request)
        return recorder.root
    }

    /// Whether a request can upgrade to HTTP/3, which runs over UDP port 443.
    static func negotiatesHTTP3() async -> Bool {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: URL(string: "https://www.google.com/generate_204")!)
        request.assumesHTTP3Capable = true
        request.timeoutInterval = 6
        for _ in 0..<3 {
            let recorder = MetricsRecorder()
            _ = try? await session.data(for: request, delegate: recorder)
            if recorder.metrics?.transactionMetrics.last?.networkProtocolName == "h3" { return true }
        }
        return false
    }

    /// The public address Cloudflare sees, over a fresh HTTPS connection.
    static func traceIP() async -> String? {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, _) = try? await session.data(from: URL(string: "https://speed.cloudflare.com/cdn-cgi/trace")!) else { return nil }
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .first { $0.hasPrefix("ip=") }
            .map { String($0.dropFirst(3)) }
    }

    /// Sends a STUN Binding Request (what video-call apps use to find their public address)
    /// over UDP. A reply proves UDP works and says which public address it came from.
    static func stunMappedAddress(host: String = "stun.l.google.com", port: UInt16 = 19302,
                                  timeout: TimeInterval = 4) async -> String? {
        let transactionID = (0..<12).map { _ in UInt8.random(in: 0...255) }
        let request = STUN.bindingRequest(transactionID: transactionID)
        return await withCheckedContinuation { continuation in
            let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .udp)
            let once = OnceFlag()
            let finish = { (address: String?) in
                guard once.claim() else { return }
                connection.cancel()
                continuation.resume(returning: address)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // UDP can drop a packet: send twice, a second apart.
                    connection.send(content: request, completion: .idempotent)
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1) { connection.send(content: request, completion: .idempotent) }
                    connection.receiveMessage { data, _, _, _ in
                        finish(data.flatMap { STUN.mappedAddress(in: $0, transactionID: transactionID) })
                    }
                case .failed:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(nil) }
        }
    }
}

/// The minimal piece of STUN (RFC 8489) needed to learn the public address: a Binding Request,
/// and the (XOR-)MAPPED-ADDRESS attribute of its response.
enum STUN {
    static let magicCookie: [UInt8] = [0x21, 0x12, 0xA4, 0x42]

    static func bindingRequest(transactionID: [UInt8]) -> Data {
        Data([0x00, 0x01, 0x00, 0x00] + magicCookie + transactionID)
    }

    static func mappedAddress(in data: Data, transactionID: [UInt8]) -> String? {
        let bytes = [UInt8](data)
        guard bytes.count >= 20, bytes[0] == 0x01, bytes[1] == 0x01,   // Binding Success Response
              Array(bytes[8..<20]) == transactionID else { return nil }
        let end = min(20 + (Int(bytes[2]) << 8 | Int(bytes[3])), bytes.count)
        var offset = 20
        while offset + 4 <= end {
            let type = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
            let length = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            let value = offset + 4
            guard value + length <= end else { break }
            // XOR-MAPPED-ADDRESS (0x0020) or legacy MAPPED-ADDRESS (0x0001), IPv4 family.
            if type == 0x0020 || type == 0x0001, length >= 8, bytes[value + 1] == 0x01 {
                var octets = Array(bytes[(value + 4)..<(value + 8)])
                if type == 0x0020 { octets = zip(octets, magicCookie).map { $0 ^ $1 } }
                return octets.map(String.init).joined(separator: ".")
            }
            offset = value + ((length + 3) & ~3)   // attributes are padded to 4 bytes
        }
        return nil
    }
}

/// Stops URLSession following redirects, so a captive portal's redirect is seen as one.
private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}

/// Records the root of a server's certificate chain. Never alters trust evaluation.
private final class TrustRecorder: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: Probes.TrustRoot?
    var root: Probes.TrustRoot? { lock.withLock { recorded } }

    private static let builtInAnchors: Set<Data> = {
        var anchors: CFArray?
        guard SecTrustCopyAnchorCertificates(&anchors) == errSecSuccess,
              let certificates = anchors as? [SecCertificate] else { return [] }
        return Set(certificates.map { SecCertificateCopyData($0) as Data })
    }()

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if let trust = challenge.protectionSpace.serverTrust,
           let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let root = chain.last {
            let name = SecCertificateCopySubjectSummary(root) as String? ?? "Unknown"
            let builtIn = Self.builtInAnchors.contains(SecCertificateCopyData(root) as Data)
            lock.withLock { recorded = Probes.TrustRoot(name: name, isBuiltIn: builtIn) }
        }
        return (.performDefaultHandling, nil)
    }
}

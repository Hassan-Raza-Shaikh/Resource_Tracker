import Foundation
import Observation

// MARK: - Measurement maths (pure, unit-tested)

enum SpeedMath {
    struct Sample: Equatable {
        let t: TimeInterval    // seconds since the transfer started
        let bytes: Int64       // cumulative bytes moved
    }

    /// One completed upload request: when it started, when the server confirmed receipt, and its size.
    struct Delivery: Equatable {
        let start: TimeInterval
        let end: TimeInterval
        let bytes: Int64
    }

    /// Cumulative bytes delivered at each time, spreading every request's bytes evenly over its
    /// own lifetime. Counting a request only at the instant it completes would make throughput
    /// arrive in steps; spreading gives a smooth curve with the same total.
    static func samples(from deliveries: [Delivery], at times: [TimeInterval]) -> [Sample] {
        times.map { t in
            let bytes = deliveries.reduce(0.0) { total, d in
                let fraction = d.end > d.start ? min(max((t - d.start) / (d.end - d.start), 0), 1) : (t >= d.end ? 1 : 0)
                return total + Double(d.bytes) * fraction
            }
            return Sample(t: t, bytes: Int64(bytes))
        }
    }

    static func mbps(bytes: Int64, seconds: TimeInterval) -> Double {
        seconds > 0 ? Double(bytes) * 8 / seconds / 1_000_000 : 0
    }

    /// Sustained throughput: everything after `rampUp`, while TCP's slow start is still opening
    /// the connections, is averaged; the ramp itself is discarded.
    static func sustainedMbps(_ samples: [Sample], after rampUp: TimeInterval) -> Double? {
        guard let start = samples.first(where: { $0.t >= rampUp }), let end = samples.last,
              end.t - start.t >= 1 else { return nil }
        return mbps(bytes: end.bytes - start.bytes, seconds: end.t - start.t)
    }

    /// Throughput over the trailing `window` seconds, for the live readout.
    static func recentMbps(_ samples: [Sample], window: TimeInterval) -> Double {
        guard let end = samples.last, let first = samples.first else { return 0 }
        let start = samples.last(where: { end.t - $0.t >= window }) ?? first
        return mbps(bytes: end.bytes - start.bytes, seconds: end.t - start.t)
    }

    /// The highest rate over any `window`-long stretch up to `until`. A network that allows a short
    /// burst before throttling shows up as a peak far above the sustained rate.
    static func peakMbps(_ samples: [Sample], until: TimeInterval, window: TimeInterval) -> Double? {
        var peak: Double?
        for (index, end) in samples.enumerated() where end.t <= until {
            guard let start = samples[..<index].last(where: { end.t - $0.t >= window }) else { continue }
            let rate = mbps(bytes: end.bytes - start.bytes, seconds: end.t - start.t)
            peak = max(peak ?? 0, rate)
        }
        return peak
    }

    /// How much the speed wobbled after ramp-up: the coefficient of variation of 1-second rates.
    static func variability(_ samples: [Sample], after rampUp: TimeInterval) -> Double? {
        let steady = samples.filter { $0.t >= rampUp }
        guard var windowStart = steady.first else { return nil }
        var rates: [Double] = []
        for sample in steady where sample.t - windowStart.t >= 1 {
            rates.append(mbps(bytes: sample.bytes - windowStart.bytes, seconds: sample.t - windowStart.t))
            windowStart = sample
        }
        guard rates.count >= 3 else { return nil }
        let mean = rates.reduce(0, +) / Double(rates.count)
        guard mean > 0 else { return nil }
        let variance = rates.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(rates.count)
        return variance.squareRoot() / mean
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// Mean absolute difference between consecutive latency samples.
    static func jitter(_ values: [Double]) -> Double? {
        guard values.count >= 2 else { return nil }
        let deltas = zip(values, values.dropFirst()).map { abs($1 - $0) }
        return deltas.reduce(0, +) / Double(deltas.count)
    }

    /// The server's own processing time, from its Server-Timing header, in ms: the sum of every
    /// `dur=` except Cloudflare's `cfL4` transport statistics. Cloudflare spends ~25 ms here even
    /// on an empty response, so leaving it in would roughly double a typical latency.
    static func serverTimingMs(_ header: String?) -> Double {
        guard let header else { return 0 }
        return header.split(separator: ",").reduce(0) { total, entry in
            let parts = entry.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let name = parts.first, name != "cfL4",
                  let dur = parts.dropFirst().first(where: { $0.hasPrefix("dur=") }),
                  let ms = Double(dur.dropFirst(4)) else { return total }
            return total + ms
        }
    }
}

/// Grades how much latency rises when the connection is busy ("bufferbloat"), on the scale
/// Waveform's widely used test popularised.
enum BufferbloatGrade: String {
    case aPlus = "A+", a = "A", b = "B", c = "C", d = "D", f = "F"

    init(increaseMs: Double) {
        switch increaseMs {
        case ..<5: self = .aPlus
        case ..<30: self = .a
        case ..<60: self = .b
        case ..<200: self = .c
        case ..<400: self = .d
        default: self = .f
        }
    }

    var summary: String {
        switch self {
        case .aPlus, .a: return "Latency barely rises under load, so calls and games stay smooth during big downloads."
        case .b: return "Latency rises a little under load; most people won’t notice."
        case .c: return "Latency rises noticeably under load, so video calls may stutter during big downloads or uploads."
        case .d, .f: return "Latency rises sharply whenever the connection is busy (bufferbloat), so calls and games will lag during downloads and uploads."
        }
    }
}

// MARK: - Result

struct SpeedTestResult: Equatable {
    var date = Date()
    var downloadMbps: Double?
    /// Set when the network let an initial burst through far faster than it sustains.
    var downloadBurstMbps: Double?
    var uploadMbps: Double?
    var downloadVariability: Double?
    var uploadVariability: Double?
    var idleLatencyMs: Double?
    var jitterMs: Double?
    var loadedLatencyDownMs: Double?
    var loadedLatencyUpMs: Double?
    var serverName: String?
    var networkName: String?
    var bytesUsed: Int64 = 0
    var link: NetworkLink?

    var bufferbloat: BufferbloatGrade? {
        guard let idle = idleLatencyMs,
              let worst = [loadedLatencyDownMs, loadedLatencyUpMs].compactMap({ $0 }).max() else { return nil }
        return BufferbloatGrade(increaseMs: max(worst - idle, 0))
    }

    /// Where the bottleneck most likely is. Deliberately hedged: only the local link rate is
    /// known for certain; everything past it is inferred.
    var verdict: String? {
        guard let down = downloadMbps, let link, let linkMbps = link.linkMbps else { return nil }
        // Usable throughput tops out around 65% of the Wi-Fi PHY rate, and ~94% of Ethernet's.
        let usable = linkMbps * (link.kind == .wifi ? 0.65 : 0.94)
        let rate = NetworkLink.rate(linkMbps)
        if down >= usable * 0.8 {
            return link.kind == .wifi
                ? "Your download is close to what this Wi-Fi link can carry (\(rate)). A stronger signal, the 5 GHz band, or Ethernet would raise it."
                : "Your download is close to your \(link.kindLabel) link’s \(rate) limit, so the link itself is the bottleneck."
        }
        return "Your \(link.kindLabel) link (\(rate)) has plenty of headroom, so the limit is beyond this Mac: your network or internet provider."
    }

    /// A burst worth reporting: at least 2.5× the sustained rate and 5 Mbps above it.
    static func burst(peak: Double?, sustained: Double?) -> Double? {
        guard let peak, let sustained, peak >= sustained * 2.5, peak - sustained >= 5 else { return nil }
        return peak
    }

    static func stability(_ variability: Double?) -> String? {
        guard let v = variability else { return nil }
        if v < 0.1 { return "Steady" }
        if v < 0.25 { return "Some variation" }
        return "Fluctuating"
    }
}

enum SpeedTestError: LocalizedError {
    case unreachable

    var errorDescription: String? {
        "Couldn’t reach the test server. Check your connection, or run Network Checks to see what’s blocked."
    }
}

// MARK: - Engine

/// An honest internet speed test against Cloudflare's global network.
///
/// - Multiple parallel TCP connections (one URLSession each, so they don't share one HTTP/2
///   connection and its single congestion window), like real downloads use.
/// - The ramp-up is discarded; the result is the sustained average after it.
/// - Uploads send random bytes, so nothing on the path can compress them and inflate the result.
/// - Latency subtracts the server's processing time, and is measured again under load.
@MainActor
@Observable
final class SpeedTest {
    enum Phase: Equatable {
        case idle, preparing, latency, download, upload, finished, cancelled
        case failed(String)

        var isRunning: Bool { [.preparing, .latency, .download, .upload].contains(self) }

        var label: String {
            switch self {
            case .preparing: return "Connecting to the nearest Cloudflare server…"
            case .latency: return "Measuring latency…"
            case .download: return "Testing download…"
            case .upload: return "Testing upload…"
            case .cancelled: return "Test stopped."
            default: return ""
            }
        }
    }

    nonisolated static let downloadStreams = 6
    nonisolated static let uploadStreams = 4
    nonisolated static let rampUp: TimeInterval = 2
    nonisolated static let measurement: TimeInterval = 8

    private(set) var phase: Phase = .idle
    private(set) var liveMbps: Double = 0
    private(set) var progress: Double = 0
    /// Filled in stage by stage while a test runs.
    private(set) var partial = SpeedTestResult()
    private(set) var result: SpeedTestResult?

    @ObservationIgnored private var task: Task<Void, Never>?

    nonisolated static func url(_ path: String, bytes: Int? = nil) -> URL {
        var components = URLComponents(string: "https://speed.cloudflare.com/\(path)")!
        if let bytes { components.queryItems = [URLQueryItem(name: "bytes", value: String(bytes))] }
        return components.url!
    }

    func start() {
        guard !phase.isRunning else { return }
        task = Task { await run() }
    }

    func stop() {
        task?.cancel()
    }

    private func run() async {
        var r = SpeedTestResult()
        partial = r
        liveMbps = 0
        progress = 0
        let probe = LatencyProbe()
        defer { probe.invalidate() }

        do {
            phase = .preparing
            r.link = await NetworkLink.current()
            async let server = ServerInfo.fetch()

            // Idle latency: one warm-up round trip, then 16 measured ones.
            phase = .latency
            _ = try? await probe.sample()
            var idle: [Double] = []
            for i in 0..<16 {
                if let ms = try? await probe.sample() { idle.append(ms) }
                progress = 0.02 + 0.08 * Double(i + 1) / 16
                try await Task.sleep(for: .milliseconds(100))
            }
            guard !idle.isEmpty else { throw SpeedTestError.unreachable }
            r.idleLatencyMs = SpeedMath.median(idle)
            r.jitterMs = SpeedMath.jitter(idle)
            let info = await server
            r.serverName = info.server
            r.networkName = info.network
            partial = r

            phase = .download
            let down = try await transfer(.download, probe: probe, progress: 0.10...0.55)
            r.downloadMbps = down.mbps
            r.downloadBurstMbps = SpeedTestResult.burst(peak: down.peak, sustained: down.mbps)
            r.downloadVariability = down.variability
            r.loadedLatencyDownMs = down.loadedLatency
            r.bytesUsed += down.bytes
            partial = r

            phase = .upload
            let up = try await transfer(.upload, probe: probe, progress: 0.55...1.0)
            r.uploadMbps = up.mbps
            r.uploadVariability = up.variability
            r.loadedLatencyUpMs = up.loadedLatency
            r.bytesUsed += up.bytes

            r.date = Date()
            partial = r
            result = r
            progress = 1
            phase = .finished
        } catch is CancellationError {
            phase = .cancelled
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
        liveMbps = 0
    }

    private struct Transfer {
        var mbps: Double?
        var peak: Double?
        var variability: Double?
        var loadedLatency: Double?
        var bytes: Int64
    }

    private func transfer(_ direction: TransferPool.Direction, probe: LatencyProbe,
                          progress range: ClosedRange<Double>) async throws -> Transfer {
        let counter = ByteCounter()
        let pool = TransferPool(direction: direction,
                                streams: direction == .download ? Self.downloadStreams : Self.uploadStreams,
                                counter: counter)
        pool.start()
        defer { pool.stop() }

        // Latency under load, on the probe's own connection, once the transfer has ramped up.
        let rampUp = Self.rampUp
        let loadedProbe = Task.detached { () -> [Double] in
            try? await Task.sleep(for: .seconds(rampUp))
            var samples: [Double] = []
            while !Task.isCancelled {
                if let ms = try? await probe.sample() { samples.append(ms) }
                try? await Task.sleep(for: .milliseconds(250))
            }
            return samples
        }
        defer { loadedProbe.cancel() }

        let total = Self.rampUp + Self.measurement
        var times: [TimeInterval] = [0]
        var samples = [SpeedMath.Sample(t: 0, bytes: 0)]
        while true {
            try await Task.sleep(for: .milliseconds(200))
            let t = pool.elapsed
            times.append(t)
            switch direction {
            case .download:
                samples.append(.init(t: t, bytes: counter.total))
                liveMbps = SpeedMath.recentMbps(samples, window: 1)
            case .upload:
                // Only confirmed deliveries count, so the live figure trails by about a second.
                liveMbps = SpeedMath.recentMbps(SpeedMath.samples(from: pool.deliveries, at: [max(t - 2, 0), t]), window: 2)
            }
            progress = range.lowerBound + (range.upperBound - range.lowerBound) * min(t / total, 1)
            if t >= total { break }
            if t >= 5, counter.total == 0 { throw SpeedTestError.unreachable }
        }
        loadedProbe.cancel()
        if direction == .upload {
            // Let requests in flight at the deadline finish, so their bytes up to it are counted.
            await pool.drain(timeout: 3)
            samples = SpeedMath.samples(from: pool.deliveries, at: times)
        }
        pool.stop()
        let loaded = await loadedProbe.value

        return Transfer(mbps: SpeedMath.sustainedMbps(samples, after: Self.rampUp),
                        peak: SpeedMath.peakMbps(samples, until: Self.rampUp + 1, window: 0.6),
                        variability: SpeedMath.variability(samples, after: Self.rampUp),
                        loadedLatency: SpeedMath.median(loaded),
                        bytes: counter.total)
    }
}

// MARK: - Plumbing

/// Thread-safe running total of bytes moved.
final class ByteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64 = 0

    func add(_ bytes: Int64) { lock.withLock { value += bytes } }
    var total: Int64 { lock.withLock { value } }
}

/// Round trips on one warm connection of their own.
final class LatencyProbe: @unchecked Sendable {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 1
        config.timeoutIntervalForRequest = 8
        session = URLSession(configuration: config)
    }

    /// One round trip in ms: request sent → first response byte, minus the server's processing time.
    func sample() async throws -> Double {
        let recorder = MetricsRecorder()
        let (_, response) = try await session.data(for: URLRequest(url: SpeedTest.url("__down", bytes: 0)), delegate: recorder)
        guard let t = recorder.metrics?.transactionMetrics.last,
              let sent = t.requestStartDate, let received = t.responseStartDate else {
            throw URLError(.badServerResponse)
        }
        let serverMs = SpeedMath.serverTimingMs((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Server-Timing"))
        return max(received.timeIntervalSince(sent) * 1000 - serverMs, 0.1)
    }

    func invalidate() {
        session.invalidateAndCancel()
    }
}

final class MetricsRecorder: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var collected: URLSessionTaskMetrics?

    var metrics: URLSessionTaskMetrics? { lock.withLock { collected } }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        lock.withLock { collected = metrics }
    }
}

/// Keeps N parallel transfers running until stopped, counting bytes as they're delivered.
///
/// Downloads count bytes as they arrive. Uploads count a request only once the server has
/// received all of it and replied: counting bytes as they're handed to the Mac's socket buffers
/// (several MB per connection) would report a fictitious burst and lumpy progress. Each upload
/// is sized to take about a second at that connection's measured rate, so slow links still
/// complete requests and fast ones aren't dominated by per-request round trips.
final class TransferPool: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Direction { case download, upload }

    /// Random, so no proxy or middlebox on the path can compress it and inflate the result.
    static let payload: Data = {
        var data = Data(count: maxUpload)
        data.withUnsafeMutableBytes { arc4random_buf($0.baseAddress, $0.count) }
        return data
    }()

    static let minUpload = 32 * 1024
    static let maxUpload = 16 * 1024 * 1024
    static let initialUpload = 64 * 1024

    private let direction: Direction
    private let streams: Int
    private let counter: ByteCounter
    private let queue = OperationQueue()
    private let lock = NSLock()
    private var sessions: [URLSession] = []
    private var stopped = false
    private var draining = false
    private let origin = Date()
    /// Upload bookkeeping, by task and by session (stream).
    private var inFlight: [Int: (bytes: Int, started: TimeInterval)] = [:]
    private var nextUploadSize: [ObjectIdentifier: Int] = [:]
    private var completed: [SpeedMath.Delivery] = []

    /// Seconds since the pool was created: the time base for samples and deliveries.
    var elapsed: TimeInterval { Date().timeIntervalSince(origin) }

    /// Upload requests the server has confirmed receiving.
    var deliveries: [SpeedMath.Delivery] { lock.withLock { completed } }

    init(direction: Direction, streams: Int, counter: ByteCounter) {
        self.direction = direction
        self.streams = streams
        self.counter = counter
        queue.maxConcurrentOperationCount = 1
    }

    func start() {
        for _ in 0..<streams {
            let config = URLSessionConfiguration.ephemeral
            config.urlCache = nil
            config.timeoutIntervalForRequest = 20
            // One session per stream: separate TCP connections, not one shared HTTP/2 connection.
            let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
            lock.withLock { sessions.append(session) }
            launch(on: session)
        }
    }

    func stop() {
        let all: [URLSession] = lock.withLock {
            stopped = true
            return sessions
        }
        all.forEach { $0.invalidateAndCancel() }
    }

    /// Stops starting new requests and waits (up to `timeout`) for those in flight to finish.
    func drain(timeout: TimeInterval) async {
        lock.withLock { draining = true }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, lock.withLock({ !inFlight.isEmpty }) {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func launch(on session: URLSession) {
        // Held across task creation so stop() can't invalidate the session in between.
        lock.lock()
        defer { lock.unlock() }
        guard !stopped, !draining else { return }
        switch direction {
        case .download:
            session.dataTask(with: URLRequest(url: SpeedTest.url("__down", bytes: 25_000_000))).resume()
        case .upload:
            let size = nextUploadSize[ObjectIdentifier(session)] ?? Self.initialUpload
            var request = URLRequest(url: SpeedTest.url("__up"))
            request.httpMethod = "POST"
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            let task = session.uploadTask(with: request, from: Self.payload.prefix(size))
            inFlight[task.taskIdentifier] = (size, elapsed)
            task.resume()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if direction == .download { counter.add(Int64(data.count)) }
    }

    /// Upload bytes put on the wire. Used only for "data used" — throughput comes from deliveries.
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if direction == .upload { counter.add(bytesSent) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if direction == .upload {
            let delivered = (task.response as? HTTPURLResponse)?.statusCode == 200 && error == nil
            let now = elapsed
            lock.withLock {
                guard let sent = inFlight.removeValue(forKey: task.taskIdentifier), delivered else { return }
                completed.append(SpeedMath.Delivery(start: sent.started, end: now, bytes: Int64(sent.bytes)))
                // Aim the next request on this stream at about a second.
                let bytesPerSecond = Double(sent.bytes) / max(now - sent.started, 0.05)
                nextUploadSize[ObjectIdentifier(session)] = min(max(Int(bytesPerSecond), Self.minUpload), Self.maxUpload)
            }
        }
        // Keep every stream busy until stopped; back off briefly after an error.
        if error == nil {
            launch(on: session)
        } else {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.launch(on: session) }
        }
    }
}

/// Which Cloudflare location served the test, and which network it came in from.
struct ServerInfo {
    var server: String?
    var network: String?

    private struct Meta: Decodable {
        struct Colo: Decodable { let iata: String?; let city: String? }
        let asn: Int?
        let asOrganization: String?
        let colo: Colo?
    }

    static func fetch() async -> ServerInfo {
        var request = URLRequest(url: SpeedTest.url("meta"))
        request.timeoutInterval = 8
        // The endpoint serves Cloudflare's own speed test page and only answers requests from it.
        request.setValue("https://speed.cloudflare.com/", forHTTPHeaderField: "Referer")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let meta = try? JSONDecoder().decode(Meta.self, from: data) else { return ServerInfo() }
        let server = meta.colo.map { colo in
            [colo.city, colo.iata.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
        }
        let network = meta.asOrganization.map(tidyOrganization).map { org in meta.asn.map { "\(org) (AS\($0))" } ?? org }
        return ServerInfo(server: server, network: network)
    }

    /// Registry descriptions are cut off mid-sentence ("PERN-Pakistan … Network is an"); drop the stub.
    static func tidyOrganization(_ name: String) -> String {
        var result = name.trimmingCharacters(in: .whitespaces)
        for stub in [" is an", " is a", " is the", " is"] where result.hasSuffix(stub) {
            result = String(result.dropLast(stub.count))
            break
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: " ,;-"))
    }
}

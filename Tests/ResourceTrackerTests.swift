import Testing
import Foundation
import SwiftUI
@testable import ResourceTracker

@Suite("Formatting")
struct FormattingTests {
    @Test func uptimeDropsLeadingZeroUnits() {
        #expect(Format.uptime(0) == "0m")
        #expect(Format.uptime(59) == "0m")
        #expect(Format.uptime(3_660) == "1h 1m")
        #expect(Format.uptime(90_000) == "1d 1h 0m")
        #expect(Format.uptime(-5) == "0m")
    }

    @Test func ratesUseDecimalUnitsLikeFinder() {
        #expect(Format.rate(0) == "0 KB/s")
        #expect(Format.rate(0.4) == "0 KB/s")
        #expect(Format.rate(1_500).hasSuffix("KB/s"))
        #expect(Format.rate(948) == "1 KB/s")            // never "948 bytes/s"
        #expect(Format.rate(2_000_000).hasPrefix("2"))  // 2 MB in decimal, not 1.9 MiB
    }

    @Test func percentAndGigabytes() {
        #expect(Format.percent(12.34) == "12.3%")
        #expect(Format.percent(12.34, decimals: 0) == "12%")
        #expect(Format.gigabytes(15.96, decimals: 0) == "16 GB")
    }
}

@Suite("Network counters")
struct NetworkDeltaTests {
    @Test func normalIncrease() {
        #expect(NetworkMonitor.delta(1_500, 1_000) == 500)
    }

    @Test func genuine32BitWrapCountsAcrossTheBoundary() {
        // 100 bytes before the top of the range → 50 bytes after wrapping = 150 transferred.
        #expect(NetworkMonitor.delta(50, UInt32.max - 99) == 150)
    }

    @Test func counterResetCountsFromZeroInsteadOfAHugeSpike() {
        // An interface bounced: 5000 → 200 must read as 200 bytes, not ~4 GB.
        #expect(NetworkMonitor.delta(200, 5_000) == 200)
    }
}

@Suite("Peak tracking")
struct PeakTrackerTests {
    @Test func floorSetsMinimumScale() {
        var t = PeakTracker(floor: 1_000, windowLength: 5)
        t.update(10)
        #expect(t.peak == 1_000)
        #expect(t.fraction(500) == 0.5)
    }

    @Test func peakIsTheWindowMaximumAndExpires() {
        var t = PeakTracker(floor: 1, windowLength: 3)
        t.update(100)
        t.update(10, 20)
        #expect(t.peak == 100)
        t.update(5)
        #expect(t.peak == 100)   // window: [100, 20, 5]
        t.update(5)
        #expect(t.peak == 20)    // 100 has left the window: [5, 20, 5]
        t.update(5)
        #expect(t.peak == 5)     // [5, 5, 5]
    }

    @Test func fractionIsClampedAndQuantized() {
        var t = PeakTracker(floor: 100, windowLength: 3)
        t.update(100)
        #expect(t.fraction(250) == 1.0)
        #expect(t.fraction(33) == 0.35)   // 5% steps
    }
}

@Suite("System status")
struct SystemStatusTests {
    @Test func heatOutranksEverything() {
        let s = SystemStatus.evaluate(thermal: .critical, pressure: .critical, cpu: 99)
        #expect(s.level == .critical)
        #expect(s.text.contains("hot"))
    }

    @Test func memoryPressureOutranksCPU() {
        let s = SystemStatus.evaluate(thermal: .nominal, pressure: .warning, cpu: 99)
        #expect(s.text.contains("Memory"))
    }

    @Test func highMemoryUseAloneIsNotAWarning() {
        // Pressure, not "percent used", decides: a full-but-healthy Mac is fine.
        let s = SystemStatus.evaluate(thermal: .nominal, pressure: .normal, cpu: 10)
        #expect(s.level == .nominal)
    }

    @Test func cpuThresholds() {
        #expect(SystemStatus.evaluate(thermal: .nominal, pressure: .normal, cpu: 70).text == "Working hard right now.")
        #expect(SystemStatus.evaluate(thermal: .nominal, pressure: .normal, cpu: 90).text == "Your Mac is under heavy load.")
    }
}

@Suite("Rendering helpers")
struct RenderingTests {
    @Test func quantizeAndBarScale() {
        #expect(Theme.quantize(12.34, step: 0.1) == 12.3)
        #expect(Theme.quantize(33, step: 5) == 35)
        #expect(Theme.quantize(0.33, step: 0.05) == 0.35)   // exact, not 0.35000000000000003
        #expect(Theme.quantize(0.07, step: 0.1) == 0.1)
        #expect(Theme.barScale(-1) == 0.01)
        #expect(Theme.barScale(2) == 1)
    }

    @Test func sparklineStaysInsideItsRect() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 50)
        let path = SparklineShape(values: [0, 100, 0, 250, -10, 50], maxValue: 100, slots: 6).path(in: rect)
        let bounds = path.boundingRect
        #expect(bounds.minY >= rect.minY - 0.5 && bounds.maxY <= rect.maxY + 0.5)
        #expect(bounds.minX >= rect.minX && bounds.maxX <= rect.maxX)
    }

    @Test func sparklineNeverDipsBelowAFlatBaseline() {
        // A flat run of zeros that then rises: Catmull-Rom overshoots below zero here;
        // the monotone curve must not.
        let rect = CGRect(x: 0, y: 0, width: 300, height: 100)
        let path = SparklineShape(values: [0, 0, 0, 0, 80, 80, 0], maxValue: 100, slots: 7).path(in: rect)
        var lowest = rect.minY
        path.cgPath.applyWithBlock { element in
            let e = element.pointee
            let count: Int
            switch e.type {
            case .moveToPoint, .addLineToPoint: count = 1
            case .addQuadCurveToPoint: count = 2
            case .addCurveToPoint: count = 3
            default: count = 0
            }
            for i in 0..<count { lowest = max(lowest, e.points[i].y) }
        }
        #expect(lowest <= rect.maxY + 0.001)
    }

    @Test func partialHistoryIsRightAligned() {
        let rect = CGRect(x: 0, y: 0, width: 290, height: 10)
        let path = SparklineShape(values: [1, 2, 3], maxValue: 3, slots: 30).path(in: rect)
        #expect(abs(path.boundingRect.maxX - rect.maxX) < 0.001)
        #expect(path.boundingRect.minX > rect.width * 0.9)
    }

    @Test func sparklineNeedsTwoPoints() {
        #expect(SparklineShape(values: [5], maxValue: 10, slots: 30).path(in: CGRect(x: 0, y: 0, width: 10, height: 10)).isEmpty)
    }

    @Test func memoryRoundingMakesInvisibleChangesEqual() {
        func info(_ active: Double) -> MemoryMonitor.MemoryInfo {
            .init(totalGB: 32, activeGB: active, wiredGB: 3, compressedGB: 1, freeGB: 10, usedGB: 14,
                  swapUsedGB: 0, usedPercentage: 43.21, pressure: .normal)
        }
        #expect(info(10.001).rounded(toGB: 0.1) == info(10.004).rounded(toGB: 0.1))
        #expect(info(10.0).rounded(toGB: 0.1) != info(10.2).rounded(toGB: 0.1))
    }
}

@Suite("Live monitors")
struct LiveMonitorTests {
    @Test func machTimebaseIsKnown() {
        #if arch(arm64)
        #expect(abs(SystemInfo.nanosecondsPerTick - 125.0 / 3.0) < 0.001)
        #else
        #expect(SystemInfo.nanosecondsPerTick == 1)
        #endif
    }

    @Test func memoryReadsAreSane() throws {
        let info = try #require(MemoryMonitor().getMemoryInfo())
        #expect(info.totalGB > 1)
        #expect((0...100).contains(info.usedPercentage))
    }

    @Test func startupVolumeIsReadable() throws {
        let disk = try #require(DiskMonitor().getDiskSpaceInfo())
        #expect(disk.totalBytes > disk.availableBytes)
        #expect((0...1).contains(disk.usedFraction))
    }

    /// Regression test for the Apple Silicon unit bug: proc_taskinfo CPU times are Mach
    /// ticks, and reading them as nanoseconds showed a fully busy core as ~2.4%.
    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func busyProcessReadsNearOneFullCore() async throws {
        let stop = ManagedAtomicFlag()
        let spinner = Thread { while !stop.isSet { _ = (0..<1_000).reduce(0, &+) } }
        spinner.start()
        defer { stop.set() }

        let monitor = ProcessMonitor()
        monitor.setActive(true)
        defer { monitor.setActive(false) }
        try await Task.sleep(for: .seconds(4.5))

        let me = try #require(monitor.topProcesses.first { $0.pid == getpid() })
        // One spinning thread ≈ 100% of a core; allow for the rest of the host and scheduling noise.
        #expect(me.cpuPercent > 60, "got \(me.cpuPercent)%")
        #expect(me.cpuPercent < 250, "got \(me.cpuPercent)%")
    }
}

/// Minimal thread-safe stop flag for the spinner thread.
final class ManagedAtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

@Suite("Speed test maths")
struct SpeedMathTests {
    typealias S = SpeedMath.Sample

    @Test func sustainedRateIgnoresRampUp() {
        // 10 Mbps for 2 s of ramp (1.25 MB/s), then a steady 100 Mbps (12.5 MB/s) for 4 s.
        var samples: [S] = [S(t: 0, bytes: 0), S(t: 1, bytes: 1_250_000), S(t: 2, bytes: 2_500_000)]
        for second in 3...6 { samples.append(S(t: Double(second), bytes: 2_500_000 + Int64(second - 2) * 12_500_000)) }
        #expect(abs(SpeedMath.sustainedMbps(samples, after: 2)! - 100) < 0.001)
        #expect(SpeedMath.sustainedMbps(samples, after: 6) == nil)   // under a second left: no answer
    }

    @Test func recentRateUsesTrailingWindow() {
        let samples = [S(t: 0, bytes: 0), S(t: 1, bytes: 1_000_000), S(t: 2, bytes: 3_000_000)]
        #expect(abs(SpeedMath.recentMbps(samples, window: 1) - 16) < 0.001)   // last second: 2 MB → 16 Mbps
    }

    @Test func peakCatchesAShortBurst() {
        // 50 Mbps for the first 0.6 s, then 5 Mbps: the shape a token-bucket shaper produces.
        let samples = [S(t: 0, bytes: 0), S(t: 0.6, bytes: 3_750_000), S(t: 1.2, bytes: 4_125_000),
                       S(t: 1.8, bytes: 4_500_000), S(t: 2.4, bytes: 4_875_000)]
        #expect(abs(SpeedMath.peakMbps(samples, until: 3, window: 0.6)! - 50) < 0.001)
        #expect(SpeedTestResult.burst(peak: 50, sustained: 5) == 50)
        #expect(SpeedTestResult.burst(peak: 11, sustained: 5) == nil)   // under 2.5×: not a burst
    }

    @Test func deliveriesSpreadEvenlyOverTheirLifetime() {
        let d = [SpeedMath.Delivery(start: 0, end: 2, bytes: 2_000), SpeedMath.Delivery(start: 1, end: 3, bytes: 1_000)]
        let s = SpeedMath.samples(from: d, at: [0, 1, 2, 3])
        #expect(s.map(\.bytes) == [0, 1_000, 2_500, 3_000])
    }

    @Test func medianAndJitter() {
        #expect(SpeedMath.median([30, 10, 20]) == 20)
        #expect(SpeedMath.median([10, 20, 30, 40]) == 25)
        #expect(SpeedMath.median([]) == nil)
        #expect(SpeedMath.jitter([10, 14, 12, 12]) == 2)   // |4| + |2| + |0| over 3
    }

    @Test func serverProcessingTimeIsSubtracted() {
        // Real headers from speed.cloudflare.com: both entries count; the cfL4 transport stats don't.
        let header = #"cfSpeedEdge;dur=3, cfSpeedWorker;dur=22, cfL4;desc="?proto=TCP&rtt=24001&min_rtt=23991""#
        #expect(SpeedMath.serverTimingMs(header) == 25)
        #expect(SpeedMath.serverTimingMs(nil) == 0)
    }

    @Test func variabilityDistinguishesSteadyFromFluctuating() {
        let steady = (0...8).map { S(t: Double($0), bytes: Int64($0) * 1_000_000) }
        #expect(SpeedTestResult.stability(SpeedMath.variability(steady, after: 0)) == "Steady")
        var bytes: Int64 = 0
        let wobbly = (0...8).map { i -> S in bytes += i.isMultiple(of: 2) ? 200_000 : 1_800_000; return S(t: Double(i), bytes: bytes) }
        #expect(SpeedTestResult.stability(SpeedMath.variability(wobbly, after: 0)) == "Fluctuating")
    }
}

@Suite("Speed test results")
struct SpeedTestResultTests {
    @Test func bufferbloatGrades() {
        #expect(BufferbloatGrade(increaseMs: 2) == .aPlus)
        #expect(BufferbloatGrade(increaseMs: 45) == .b)
        #expect(BufferbloatGrade(increaseMs: 150) == .c)
        #expect(BufferbloatGrade(increaseMs: 900) == .f)
        var r = SpeedTestResult()
        r.idleLatencyMs = 20; r.loadedLatencyDownMs = 90; r.loadedLatencyUpMs = 40
        #expect(r.bufferbloat == .c)   // graded on the worse direction: +70 ms
    }

    @Test func verdictBlamesTheLinkOnlyWhenNearItsLimit() {
        var r = SpeedTestResult()
        r.link = link(.ethernet, mbps: 1000)
        r.downloadMbps = 900
        #expect(r.verdict?.contains("link itself is the bottleneck") == true)
        r.downloadMbps = 7
        #expect(r.verdict?.contains("beyond this Mac") == true)
    }

    @Test func linkRatesFormat() {
        #expect(NetworkLink.rate(1000) == "1 Gbps")
        #expect(NetworkLink.rate(2500) == "2.5 Gbps")
        #expect(NetworkLink.rate(866) == "866 Mbps")
        #expect(Format.mbps(6.83) == "6.8 Mbps")
        #expect(Format.mbps(940) == "940 Mbps")
        #expect(Format.mbps(1234) == "1.23 Gbps")
    }

    @Test func truncatedRegistryNamesAreTidied() {
        #expect(ServerInfo.tidyOrganization("PERN-Pakistan Education & Research Network is an") == "PERN-Pakistan Education & Research Network")
        #expect(ServerInfo.tidyOrganization("Cloudflare, Inc.") == "Cloudflare, Inc.")
    }

    private func link(_ kind: NetworkLink.Kind, mbps: Double) -> NetworkLink {
        NetworkLink(kind: kind, interfaceName: "en0", linkMbps: mbps, isExpensive: false, isConstrained: false, usesVPN: false)
    }
}

@Suite("STUN")
struct STUNTests {
    let transactionID: [UInt8] = Array(1...12)

    @Test func bindingRequestIsWellFormed() {
        let request = [UInt8](STUN.bindingRequest(transactionID: transactionID))
        #expect(request.count == 20)
        #expect(Array(request[0..<4]) == [0x00, 0x01, 0x00, 0x00])        // Binding Request, no attributes
        #expect(Array(request[4..<8]) == [0x21, 0x12, 0xA4, 0x42])        // magic cookie
        #expect(Array(request[8..<20]) == transactionID)
    }

    @Test func xorMappedAddressDecodes() {
        // 182.176.222.243 XOR-ed with the magic cookie, as a server would send it.
        let ip: [UInt8] = [182, 176, 222, 243]
        let xored = zip(ip, STUN.magicCookie).map { $0 ^ $1 }
        let attribute: [UInt8] = [0x00, 0x20, 0x00, 0x08, 0x00, 0x01, 0x12, 0x34] + xored
        let response = Data([0x01, 0x01, 0x00, UInt8(attribute.count)] + STUN.magicCookie + transactionID + attribute)
        #expect(STUN.mappedAddress(in: response, transactionID: transactionID) == "182.176.222.243")
    }

    @Test func rejectsSomeoneElsesResponse() {
        let response = Data([0x01, 0x01, 0x00, 0x00] + STUN.magicCookie + Array(repeating: 9, count: 12))
        #expect(STUN.mappedAddress(in: response, transactionID: transactionID) == nil)
    }
}

import SwiftUI

extension Format {
    /// Speed-test units: megabits per second (decimal), the convention every ISP advertises in.
    static func mbps(_ value: Double) -> String {
        if value >= 1000 { return String(format: "%.2f Gbps", value / 1000) }
        if value >= 100 { return String(format: "%.0f Mbps", value) }
        return String(format: "%.1f Mbps", value)
    }

    static func ms(_ value: Double) -> String {
        String(format: "%.0f ms", value)
    }
}

// MARK: - Speed test

struct SpeedTestCard: View {
    @Environment(SpeedTest.self) private var test
    @State private var link: NetworkLink?
    @State private var showMethodology = false
    @State private var confirmMetered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(icon: "speedometer", title: "Speed Test", tint: Theme.ocean) {
                HStack(spacing: 12) {
                    Button {
                        showMethodology = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("How this test works")
                    .popover(isPresented: $showMethodology, arrowEdge: .bottom) { MethodologyView() }
                    runButton
                }
            }

            if test.phase.isRunning {
                running
            } else if let result = test.result {
                ResultView(result: result)
            } else {
                Text("Measures sustained download and upload speed over several connections, plus latency when idle and when the line is busy. Takes about 25 seconds.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case .failed(let message) = test.phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(Theme.alert)
            } else if test.phase == .cancelled {
                Text(test.phase.label).font(.callout).foregroundStyle(.secondary)
            }

            if let link, !test.phase.isRunning, test.result == nil {
                Label("Testing over \(link.summary)", systemImage: link.kind == .wifi ? "wifi" : "cable.connector")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .glassCard()
        .task { link = await NetworkLink.current() }
        .confirmationDialog("This connection is metered or in Low Data Mode", isPresented: $confirmMetered) {
            Button("Run Test Anyway") { test.start() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A speed test transfers as much data as your connection can carry for about 20 seconds, which can be over 1 GB on a fast line.")
        }
    }

    private var runButton: some View {
        Group {
            if test.phase.isRunning {
                Button("Stop") { test.stop() }
                    .buttonStyle(.glass)
            } else {
                Button(test.result == nil ? "Run Test" : "Run Again") { start() }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.ocean)
            }
        }
        .controlSize(.regular)
    }

    private func start() {
        Task {
            let current = await NetworkLink.current()
            link = current
            if current?.isExpensive == true || current?.isConstrained == true {
                confirmMetered = true
            } else {
                test.start()
            }
        }
    }

    private var running: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(test.phase.label).foregroundStyle(.secondary)
                Spacer()
                if test.phase == .download || test.phase == .upload {
                    Label(Format.mbps(test.liveMbps), systemImage: test.phase == .download ? "arrow.down" : "arrow.up")
                        .metricFont(.title)
                        .foregroundStyle(test.phase == .download ? Theme.ocean : Theme.rose)
                        .contentTransition(.numericText())
                }
            }
            FillBar(fraction: test.progress, color: Theme.ocean, height: 6)
            HStack(spacing: 18) {
                if let ms = test.partial.idleLatencyMs { Text("Latency \(Format.ms(ms))") }
                if let down = test.partial.downloadMbps { Text("Download \(Format.mbps(down))") }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}

private struct ResultView: View {
    let result: SpeedTestResult

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 4) {
                GridRow {
                    headline("Download", "arrow.down", Theme.ocean)
                    headline("Upload", "arrow.up", Theme.rose)
                    headline("Latency", "timer", Theme.sage)
                }
                GridRow {
                    metric(result.downloadMbps.map(Format.mbps), Theme.ocean)
                    metric(result.uploadMbps.map(Format.mbps), Theme.rose)
                    metric(result.idleLatencyMs.map(Format.ms), Theme.sage)
                }
                GridRow {
                    caption(SpeedTestResult.stability(result.downloadVariability) ?? "Sustained")
                    caption(SpeedTestResult.stability(result.uploadVariability) ?? "Sustained")
                    caption(result.jitterMs.map { "± \(Format.ms($0)) jitter" } ?? "Idle")
                }
            }

            if let grade = result.bufferbloat {
                HStack(alignment: .top, spacing: 12) {
                    GradeBadge(grade: grade)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 14) {
                            Text("Latency under load").font(.subheadline.weight(.semibold))
                            if let down = result.loadedLatencyDownMs { Label(Format.ms(down), systemImage: "arrow.down") }
                            if let up = result.loadedLatencyUpMs { Label(Format.ms(up), systemImage: "arrow.up") }
                        }
                        .font(.subheadline.monospacedDigit())
                        Text(grade.summary).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let burst = result.downloadBurstMbps, let sustained = result.downloadMbps {
                Label {
                    Text("This network lets short bursts through at up to \(Format.mbps(burst)), then holds sustained downloads to \(Format.mbps(sustained)). Tests that finish within a second or two report the burst.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "bolt.horizontal.fill").foregroundStyle(Theme.amber)
                }
                .font(.callout)
            }

            if let verdict = result.verdict {
                Label {
                    Text(verdict).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lightbulb").foregroundStyle(Theme.amber)
                }
                .font(.callout)
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                if let server = result.serverName { detail("Server", "Cloudflare · \(server)") }
                if let network = result.networkName { detail("Network", network) }
                if let link = result.link { detail("Connection", link.summary) }
                detail("Data used", Format.storage(result.bytesUsed))
                detail("Tested", result.date.formatted(date: .omitted, time: .shortened))
            }
            .font(.caption)
        }
    }

    private func headline(_ title: String, _ icon: String, _ color: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
    }

    private func metric(_ value: String?, _ color: Color) -> some View {
        Text(value ?? "—").metricFont(.title).foregroundStyle(color)
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}

private struct GradeBadge: View {
    let grade: BufferbloatGrade

    private var color: Color {
        switch grade {
        case .aPlus, .a: return Theme.sage
        case .b, .c: return Theme.amber
        case .d, .f: return Theme.alert
        }
    }

    var body: some View {
        Text(grade.rawValue)
            .font(.system(.title2, design: .rounded).bold())
            .foregroundStyle(color)
            .frame(width: 44, height: 44)
            .background(color.opacity(0.14), in: .rect(cornerRadius: 10))
            .accessibilityLabel("Bufferbloat grade \(grade.rawValue)")
    }
}

private struct MethodologyView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How this test works").font(.headline)
            point("server.rack", "Tests against Cloudflare’s global network, not a server inside your provider’s network, so a provider can’t give the test special treatment.")
            point("arrow.left.arrow.right", "Downloads use \(SpeedTest.downloadStreams) parallel connections and uploads \(SpeedTest.uploadStreams), enough to fill fast links the way real downloads do.")
            point("chart.line.uptrend.xyaxis", "The first \(Int(SpeedTest.rampUp)) seconds, while connections speed up, are discarded. The result is the sustained average over the next \(Int(SpeedTest.measurement)).")
            point("dice", "Uploads send random data, so nothing along the way can compress it and inflate the result.")
            point("timer", "Latency is the median of 16 round trips with the server’s own processing time subtracted, then measured again while the line is busy. The difference is bufferbloat.")
            point("map", "Results reflect the route to the nearest Cloudflare server. Other destinations can be faster or slower.")
        }
        .padding(18)
        .frame(width: 380)
    }

    private func point(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).foregroundStyle(Theme.ocean).frame(width: 18)
        }
        .font(.callout)
    }
}

// MARK: - Network checks

struct NetworkChecksCard: View {
    @Environment(NetworkDiagnostics.self) private var diagnostics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(icon: "checkmark.shield", title: "Network Checks", tint: Theme.sage) {
                Button(diagnostics.isRunning ? "Checking…" : (diagnostics.checks.isEmpty ? "Run Checks" : "Check Again")) {
                    diagnostics.run()
                }
                .buttonStyle(.glass)
                .disabled(diagnostics.isRunning)
            }

            if diagnostics.checks.isEmpty {
                Text("Looks for restrictions on this network: blocked ports and protocols, captive portals, HTTPS inspection, DNS tampering, and more. Takes a few seconds.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if diagnostics.finishedAt != nil { summary }
                ForEach(NetworkDiagnostics.Group.allCases, id: \.self) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.rawValue)
                            .font(.system(.caption, design: .rounded).bold())
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        ForEach(diagnostics.checks.filter { $0.id.group == group }) { CheckRow(check: $0) }
                    }
                }
            }
        }
        .glassCard()
    }

    private var summary: some View {
        let issues = diagnostics.issues
        return Label {
            Text(issues.isEmpty
                 ? "No restrictions found. This network lets everything through."
                 : "\(issues.count) restriction\(issues.count == 1 ? "" : "s") found: \(issues.map { $0.id.title }.joined(separator: ", ")).")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: issues.isEmpty ? "checkmark.seal.fill" : "exclamationmark.shield.fill")
                .foregroundStyle(issues.isEmpty ? Theme.sage : Theme.amber)
        }
        .font(.callout.weight(.medium))
    }
}

private struct CheckRow: View {
    let check: NetworkDiagnostics.Check

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            icon.frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(check.id.title)
                    Spacer(minLength: 12)
                    Text(check.value)
                        .foregroundStyle(valueColor)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
                if let note = check.note, check.status != .ok {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.callout.monospacedDigit())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var icon: some View {
        switch check.status {
        case .pending: ProgressView().controlSize(.mini)
        case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.sage)
        case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
        case .blocked: Image(systemName: "xmark.octagon.fill").foregroundStyle(Theme.alert)
        case .info: Image(systemName: "info.circle.fill").foregroundStyle(.secondary)
        }
    }

    private var valueColor: Color {
        switch check.status {
        case .warning: return Theme.amber
        case .blocked: return Theme.alert
        default: return .secondary
        }
    }
}

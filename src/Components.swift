import SwiftUI

// MARK: - Cards

extension View {
    /// A Liquid Glass card that fills its grid cell, so cards in a row share a height.
    func glassCard(alignment: Alignment = .topLeading) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    /// Rounded, monospaced-digit metric text. Constant digit widths mean a changing
    /// number never re-lays-out its neighbours or jitters horizontally.
    func metricFont(_ style: Font.TextStyle) -> some View {
        font(.system(style, design: .rounded).monospacedDigit().bold())
    }
}

/// Icon + small-caps title on the left, optional accessory on the right.
struct CardHeader<Accessory: View>: View {
    let icon: String
    let title: String
    var tint: Color = .secondary
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(.caption, design: .rounded).bold())
                .textCase(.uppercase)
                .kerning(0.4)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            accessory
        }
    }
}

extension CardHeader where Accessory == EmptyView {
    init(icon: String, title: String, tint: Color = .secondary) {
        self.init(icon: icon, title: title, tint: tint) { EmptyView() }
    }
}

// MARK: - Buttons

struct TactileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Sparkline

/// A smooth line through evenly spaced samples, drawn as a plain Shape: for a 30-point
/// line, Swift Charts' layout engine cost more than the rest of the card.
///
/// Uses monotone cubic interpolation (Fritsch–Carlson), so the curve never overshoots
/// the data — no dips below zero where a flat line starts to rise. Samples fill `slots`
/// from the right, so a history that's still filling up starts partway across.
struct SparklineShape: Shape {
    var values: [Double]
    var maxValue: Double
    var slots: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let n = values.count
        guard n > 1, slots > 1, rect.width > 0, rect.height > 0 else { return path }
        let step = rect.width / CGFloat(slots - 1)
        let startX = rect.maxX - CGFloat(n - 1) * step
        let scale = maxValue > 0 ? maxValue : 1
        let points = values.enumerated().map { i, v in
            CGPoint(x: startX + CGFloat(i) * step,
                    y: rect.maxY - CGFloat(min(max(v / scale, 0), 1)) * rect.height)
        }

        // Secant slopes, then tangents limited so each segment stays monotone.
        let secants = (0..<(n - 1)).map { (points[$0 + 1].y - points[$0].y) / step }
        var tangents = [CGFloat](repeating: 0, count: n)
        tangents[0] = secants[0]
        tangents[n - 1] = secants[n - 2]
        for i in 1..<(n - 1) {
            tangents[i] = secants[i - 1] * secants[i] <= 0 ? 0 : (secants[i - 1] + secants[i]) / 2
        }
        for i in 0..<(n - 1) {
            guard secants[i] != 0 else { tangents[i] = 0; tangents[i + 1] = 0; continue }
            let a = tangents[i] / secants[i], b = tangents[i + 1] / secants[i]
            let h = a * a + b * b
            if h > 9 {
                let t = 3 / h.squareRoot()
                tangents[i] = t * a * secants[i]
                tangents[i + 1] = t * b * secants[i]
            }
        }

        path.move(to: points[0])
        for i in 0..<(n - 1) {
            let c1 = CGPoint(x: points[i].x + step / 3, y: points[i].y + tangents[i] * step / 3)
            let c2 = CGPoint(x: points[i + 1].x - step / 3, y: points[i + 1].y - tangents[i + 1] * step / 3)
            path.addCurve(to: points[i + 1], control1: c1, control2: c2)
        }
        return path
    }
}

/// One or more series drawn over a shared vertical scale.
struct Sparkline: View {
    struct Series {
        let data: [ChartDataPoint]
        let color: Color
    }

    let series: [Series]
    /// Fixed top of the scale (e.g. 100 for percentages); nil scales to the data.
    var maxValue: Double? = nil
    /// When scaling to the data, never use a top below this — so a trickle of idle
    /// network traffic stays a flat line instead of filling the graph.
    var minimumScale: Double = 0

    init(_ data: [ChartDataPoint], color: Color, maxValue: Double? = nil) {
        self.series = [Series(data: data, color: color)]
        self.maxValue = maxValue
    }

    init(series: [Series], minimumScale: Double = 0) {
        self.series = series
        self.minimumScale = minimumScale
    }

    var body: some View {
        let peak = maxValue ?? max(minimumScale, series.flatMap { $0.data.map(\.value) }.max() ?? 0)
        ZStack {
            ForEach(series.indices, id: \.self) { index in
                let s = series[index]
                SparklineShape(values: s.data.map(\.value), maxValue: peak > 0 ? peak : 1,
                               slots: MonitorViewModel.historyLength)
                    .stroke(
                        // Older samples fade out; the newest is at full strength.
                        LinearGradient(colors: [s.color.opacity(0.35), s.color], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round)
                    )
            }
        }
        .padding(1)  // keep round caps inside the frame
        .accessibilityHidden(true)  // the adjacent numeric readout carries the value
    }
}

struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 10, height: 3)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Gauges

struct GlassRingGauge: View {
    let value: Double
    let color: Color
    let label: String
    var accessibilityName: String = ""

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 12)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(value / 100.0, 0), 1)))
                .stroke(
                    AngularGradient(colors: [color.opacity(0.7), color], center: .center),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(Theme.valueAnimation, value: value)
            VStack(spacing: 1) {
                Text("\(Int(value))%")
                    .metricFont(.title2)
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 96, height: 96)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName.isEmpty ? label : accessibilityName)
        .accessibilityValue("\(Int(value)) percent")
    }
}

/// Label, value, and a fill bar for a throughput-style metric.
struct ActivityGaugeRow: View {
    let label: String
    let value: String
    let fraction: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(value).metricFont(.title3).foregroundStyle(color)
            }
            FillBar(fraction: fraction, color: color, height: 5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

/// A capsule track with a gradient fill.
struct FillBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 5

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.primary.opacity(0.08))
            Capsule()
                .fill(LinearGradient(colors: [color.opacity(0.6), color], startPoint: .leading, endPoint: .trailing))
                // scaleEffect is a render-only transform: animating it never invalidates
                // layout, unlike animating .frame(width:).
                .scaleEffect(x: Theme.barScale(fraction), y: 1, anchor: .leading)
                .animation(Theme.valueAnimation, value: fraction)
        }
        .frame(height: height)
    }
}

// MARK: - Pills & badges

struct StatusPill: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.caption)
            Text(text).font(.caption.bold())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

struct SidebarBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.monospacedDigit().weight(.medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tint.opacity(0.2), in: .capsule)
    }
}

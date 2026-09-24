import SwiftUI

extension Color {
    /// A colour with separate values for light and dark appearance. The muted palette
    /// reads well on light glass but disappears on dark, so dark variants are lifted.
    init(light: (Double, Double, Double), dark: (Double, Double, Double)) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

/// Palette, animation, and formatting shared across every view.
enum Theme {
    static let sage = Color(light: (0.36, 0.50, 0.42), dark: (0.56, 0.76, 0.64))
    static let amber = Color(light: (0.78, 0.56, 0.26), dark: (0.93, 0.74, 0.43))
    static let terracotta = Color(light: (0.74, 0.40, 0.28), dark: (0.93, 0.58, 0.46))
    static let ocean = Color(light: (0.27, 0.46, 0.60), dark: (0.50, 0.70, 0.86))
    static let rose = Color(light: (0.74, 0.36, 0.48), dark: (0.93, 0.56, 0.66))
    static let amethyst = Color(light: (0.52, 0.38, 0.82), dark: (0.72, 0.60, 0.97))
    static let alert = Color(light: (0.80, 0.26, 0.24), dark: (0.98, 0.44, 0.41))

    /// Animation for values that refresh on the 1s sampling timer. Deliberately short
    /// with a hard end: a spring (response ~0.5–0.7s) takes longer than the sampling
    /// interval to settle, gets retargeted before it finishes, and keeps the app
    /// rendering at display refresh rate forever.
    static let valueAnimation: Animation = .easeOut(duration: 0.35)

    /// Snap a value to a visible step so sub-pixel jitter between samples doesn't
    /// retrigger an animation (each animated frame re-composites the Liquid Glass card).
    static func quantize(_ value: Double, step: Double) -> Double {
        // For decimal steps like 0.05, divide by the integral reciprocal instead of
        // multiplying by the step, so results land exactly on the nearest decimal
        // (0.35, not 0.35000000000000003).
        let inverse = (1 / step).rounded()
        if step < 1, abs(inverse * step - 1) < 1e-9 {
            return (value * inverse).rounded() / inverse
        }
        return (value / step).rounded() * step
    }

    /// Horizontal scale for a fill bar, clamped so an idle bar still shows a hairline.
    static func barScale(_ fraction: Double) -> CGFloat {
        CGFloat(min(max(fraction, 0.01), 1.0))
    }

    /// Colour for a CPU- or GPU-style load percentage.
    static func loadColor(_ percent: Double) -> Color {
        if percent > 85 { return alert }
        if percent > 65 { return amber }
        return sage
    }

    static func color(for level: StatusLevel) -> Color {
        switch level {
        case .nominal: return sage
        case .elevated: return amber
        case .critical: return alert
        }
    }

    static func color(for pressure: MemoryPressure) -> Color {
        switch pressure {
        case .normal: return sage
        case .warning: return amber
        case .critical: return alert
        }
    }

    static func color(for thermal: ProcessInfo.ThermalState) -> Color {
        switch thermal {
        case .nominal: return sage
        case .fair: return amber
        case .serious: return terracotta
        case .critical: return alert
        @unknown default: return .secondary
        }
    }
}

/// Human-readable numbers, matching the conventions macOS itself uses.
enum Format {
    /// Disk and network use decimal units (1 KB = 1000 B), as Finder and Activity Monitor do.
    private static let fileFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    /// Memory uses binary units, as Activity Monitor does.
    private static let memoryFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .memory
        return f
    }()

    /// Rates never drop below KB, so a quiet link reads "1 KB/s", not "948 bytes/s".
    private static let rateFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f
    }()

    static func rate(_ bytesPerSecond: Double) -> String {
        // The formatter spells zero as "Zero KB".
        bytesPerSecond < 1 ? "0 KB/s" : rateFormatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }

    static func storage(_ bytes: Int64) -> String {
        fileFormatter.string(fromByteCount: bytes)
    }

    static func memory(_ bytes: UInt64) -> String {
        memoryFormatter.string(fromByteCount: Int64(bytes))
    }

    static func gigabytes(_ gb: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f GB", gb)
    }

    static func percent(_ value: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f%%", value)
    }

    /// "6d 23h 37m", dropping leading zero units ("4h 5m", "12m").
    static func uptime(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        let days = total / 86_400, hours = (total % 86_400) / 3_600, mins = (total % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h \(mins)m" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    static func thermal(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Normal"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}

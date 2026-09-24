// Renders every Resource Tracker icon asset from code, so the artwork is exact at each size
// and can be tweaked and regenerated:
//
//     swiftc -O -o /tmp/render_icon scripts/render_icon.swift && /tmp/render_icon
//
// Outputs (paths relative to the repo root, which must be the working directory):
//   ResourceTracker/Assets.xcassets/AppIcon.appiconset/icon_*.png   app icon, all 10 macOS sizes
//   ResourceTracker/Assets.xcassets/MenuBarIcon.imageset/*.pdf       menu bar template glyph (vector)
//   assets/AppIcon.png                                               1024 px master (README, build.sh)
//
// Design: a gauge (how much of the Mac is in use) around a pulse (live), in white on a warm
// amber → coral gradient. Follows the macOS icon grid: an 824 px continuous-corner body
// centred on a 1024 px transparent canvas.

import SwiftUI
import AppKit

// MARK: - Shapes

/// Flat → spike up → spike down → flat.
struct Pulse: Shape {
    func path(in r: CGRect) -> Path {
        let points: [(CGFloat, CGFloat)] = [(0, 0.55), (0.30, 0.55), (0.42, 0.06), (0.58, 0.96), (0.70, 0.55), (1, 0.55)]
        var p = Path()
        p.move(to: CGPoint(x: r.minX + points[0].0 * r.width, y: r.minY + points[0].1 * r.height))
        for (x, y) in points.dropFirst() { p.addLine(to: CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height)) }
        return p
    }
}

/// A 270° gauge open at the bottom, filled to `fraction` of its sweep.
struct Gauge: View {
    var fraction: CGFloat
    var lineWidth: CGFloat
    var track: Color
    var fill: Color

    var body: some View {
        ZStack {
            Circle().trim(from: 0, to: 0.75)
                .stroke(track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle().trim(from: 0, to: 0.75 * fraction)
                .stroke(fill, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        .rotationEffect(.degrees(135))
    }
}

/// The mark itself, laid out in a unit square of side `size`. `bold` thickens strokes for
/// small renderings, the way Apple hand-tunes icons at 16–64 px.
struct Mark: View {
    var size: CGFloat
    var bold: Bool
    var ink: Color
    var track: Color

    var body: some View {
        let ring = size * (bold ? 0.17 : 0.128)
        ZStack {
            Gauge(fraction: 0.66, lineWidth: ring, track: track, fill: ink)
            Pulse()
                .stroke(ink, style: StrokeStyle(lineWidth: size * (bold ? 0.12 : 0.084), lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.58, height: size * (bold ? 0.38 : 0.34))
                .offset(y: size * 0.012)
        }
        .frame(width: size - ring, height: size - ring)
        .frame(width: size, height: size)
    }
}

// MARK: - App icon

struct AppIcon: View {
    var bold: Bool

    static let top = Color(red: 1.00, green: 0.71, blue: 0.28)     // amber
    static let bottom = Color(red: 0.96, green: 0.32, blue: 0.23)  // coral red

    var body: some View {
        let body = RoundedRectangle(cornerRadius: 185, style: .continuous)
        ZStack {
            body
                .fill(LinearGradient(colors: [Self.top, Self.bottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(body.fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center)))
                .frame(width: 824, height: 824)
            Mark(size: 520, bold: bold, ink: .white, track: .white.opacity(bold ? 0.4 : 0.3))
                .shadow(color: Color(red: 0.62, green: 0.16, blue: 0.08).opacity(0.28), radius: 14, y: 10)
                .offset(y: 16)
        }
        .frame(width: 1024, height: 1024)
    }
}

// MARK: - Output

@MainActor func png(_ view: some View, pixels: Int, to path: String) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = CGFloat(pixels) / 1024
    guard let image = renderer.cgImage else { fatalError("render failed: \(path)") }
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

/// The menu bar glyph, drawn with Core Graphics paths so the PDF is true vector (SwiftUI's
/// renderer can rasterise strokes). Stroke weights match SF Symbols at menu bar size.
func menuBarGlyph(points side: CGFloat, to path: String) {
    var box = CGRect(x: 0, y: 0, width: side, height: side)
    guard let ctx = CGContext(URL(fileURLWithPath: path) as CFURL, mediaBox: &box, nil) else { fatalError("pdf: \(path)") }
    ctx.beginPDFPage(nil)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // PDF space is y-up: start at bottom-left (225°), sweep 270° clockwise over the top.
    let ring: CGFloat = 1.7
    let center = CGPoint(x: side / 2, y: side / 2 - 0.2)
    let radius = side / 2 - ring / 2 - 0.6
    let start = CGFloat.pi * 1.25, sweep = CGFloat.pi * 1.5
    func arc(to fraction: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.addArc(center: center, radius: radius, startAngle: start, endAngle: start - sweep * fraction, clockwise: true)
        return p
    }
    ctx.setLineWidth(ring)
    ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.35)); ctx.addPath(arc(to: 1)); ctx.strokePath()
    ctx.setStrokeColor(CGColor(gray: 0, alpha: 1)); ctx.addPath(arc(to: 0.66)); ctx.strokePath()

    // Pulse, in the same proportions as the app icon's.
    let w = side * 0.56, h = side * 0.34
    let origin = CGPoint(x: center.x - w / 2, y: center.y - h / 2)
    let points: [(CGFloat, CGFloat)] = [(0, 0.45), (0.30, 0.45), (0.42, 0.94), (0.58, 0.04), (0.70, 0.45), (1, 0.45)]
    let pulse = CGMutablePath()
    pulse.addLines(between: points.map { CGPoint(x: origin.x + $0.0 * w, y: origin.y + $0.1 * h) })
    ctx.setLineWidth(1.5)
    ctx.addPath(pulse); ctx.strokePath()

    ctx.endPDFPage()
    ctx.closePDF()
}

MainActor.assumeIsolated {
    let iconSet = "ResourceTracker/Assets.xcassets/AppIcon.appiconset"
    let sizes: [(name: String, pixels: Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]
    for s in sizes {
        png(AppIcon(bold: s.pixels <= 64), pixels: s.pixels, to: "\(iconSet)/\(s.name).png")
    }
    png(AppIcon(bold: false), pixels: 1024, to: "assets/AppIcon.png")

    // Menu bar: black + alpha only; macOS tints it (template image) for light/dark menu bars.
    menuBarGlyph(points: 18, to: "ResourceTracker/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.pdf")
    print("Rendered \(sizes.count) app icon sizes, the master PNG, and the menu bar glyph.")
}

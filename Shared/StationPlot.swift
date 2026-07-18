import SwiftUI

/// A faithful SwiftUI `Canvas` port of `weather_circle.py` from
/// yeled/weather-circles. All geometry lives in the original 260×260 SVG
/// user space and is scaled uniformly to fit the view, so every proportion
/// matches the TRMNL renderer: R=64 circle with 7-unit strokes, 50-unit
/// barb shaft, present-weather glyph left of the circle, temperature
/// top-right.
struct StationPlot: View {
    var observation: StationObservation
    /// Symbol colour. Defaults to the repo's inks: #1a1a2e on light
    /// backgrounds, #eef2f8 (its suggested `--ink` for dark) on dark.
    var ink: Color?
    /// Draw the precip glyph in ink rather than its tint — the repo's
    /// `--mono` flag, right for e-ink-ish surfaces like the lock screen.
    var mono: Bool = false
    var showTemperature: Bool = true
    /// Casing drawn under the barb so it survives a solid 8-okta disc
    /// (`halo` in the Python). Pass the view's background colour.
    var haloColor: Color?

    @Environment(\.colorScheme) private var colorScheme

    // ── Geometry (SVG user units) ── SIZE/CX/CY/R/BARB_LEN/STROKE verbatim.
    private enum G {
        static let size = 260.0
        static let cx = 130.0, cy = 130.0
        static let r = 64.0
        static let barbLen = 50.0
        static let stroke = 7.0
    }

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / G.size
            context.translateBy(x: (size.width - G.size * scale) / 2,
                                y: (size.height - G.size * scale) / 2)
            context.scaleBy(x: scale, y: scale)

            let ink = resolvedInk
            drawOktas(&context, ink: ink)
            drawBarb(&context, ink: ink, halo: haloColor)
            drawPresentWeather(&context, ink: ink)
            if showTemperature {
                let label = Text("\(observation.roundedTemp)°")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(ink)
                context.draw(label,
                             at: CGPoint(x: G.cx + G.r * 0.5, y: G.cy - G.r - 6),
                             anchor: .bottomLeading)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(Text(observation.accessibilitySummary))
    }

    private var resolvedInk: Color {
        ink ?? (colorScheme == .dark ? Color(hex: 0xEEF2F8) : Color(hex: 0x1A1A2E))
    }

    // ── Path helpers ───────────────────────────────────────────────────

    /// Point on a circle, angle measured clockwise from 12 o'clock (`pt`).
    private func pt(_ radius: Double, _ degFromTop: Double) -> CGPoint {
        let a = degFromTop * .pi / 180
        return CGPoint(x: G.cx + radius * sin(a), y: G.cy - radius * cos(a))
    }

    /// Filled pie slice, clockwise from `startDeg` spanning `sweepDeg`
    /// (`wedge`). In SwiftUI's y-down space, `clockwise: false` sweeps
    /// clockwise on screen — the SVG arc's `sweep=1`.
    private func wedge(startDeg: Double, sweepDeg: Double) -> Path {
        var path = Path()
        let center = CGPoint(x: G.cx, y: G.cy)
        path.move(to: center)
        path.addLine(to: pt(G.r, startDeg))
        path.addArc(center: center, radius: G.r,
                    startAngle: .degrees(startDeg - 90),
                    endAngle: .degrees(startDeg + sweepDeg - 90),
                    clockwise: false)
        path.closeSubpath()
        return path
    }

    private func segment(from a: CGPoint, to b: CGPoint) -> Path {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        return path
    }

    private func strokeLine(_ context: inout GraphicsContext,
                            from a: CGPoint, to b: CGPoint,
                            color: Color, width: Double) {
        context.stroke(segment(from: a, to: b), with: .color(color),
                       style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private func circlePath(center: CGPoint, radius: Double) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                               width: radius * 2, height: radius * 2))
    }

    // ── Cloud cover (oktas) — port of draw_oktas ───────────────────────

    private func drawOktas(_ context: inout GraphicsContext, ink: Color) {
        let center = CGPoint(x: G.cx, y: G.cy)
        context.stroke(circlePath(center: center, radius: G.r),
                       with: .color(ink), lineWidth: G.stroke)

        if observation.skyObscured {                     // sky obscured -> X
            let d = G.r * 0.6
            strokeLine(&context, from: CGPoint(x: G.cx - d, y: G.cy - d),
                       to: CGPoint(x: G.cx + d, y: G.cy + d), color: ink, width: G.stroke)
            strokeLine(&context, from: CGPoint(x: G.cx + d, y: G.cy - d),
                       to: CGPoint(x: G.cx - d, y: G.cy + d), color: ink, width: G.stroke)
            return
        }

        func vline() {
            strokeLine(&context, from: CGPoint(x: G.cx, y: G.cy - G.r),
                       to: CGPoint(x: G.cx, y: G.cy + G.r), color: ink, width: G.stroke)
        }
        func hline() {
            strokeLine(&context, from: CGPoint(x: G.cx - G.r, y: G.cy),
                       to: CGPoint(x: G.cx + G.r, y: G.cy), color: ink, width: G.stroke)
        }
        func fill(_ sweep: Double) {
            context.fill(wedge(startDeg: 0, sweepDeg: sweep), with: .color(ink))
        }

        switch observation.oktas {
        case ..<1: break
        case 1:    vline()
        case 2:    fill(90)
        case 3:    fill(90); vline()
        case 4:    fill(180)
        case 5:    fill(180); hline()
        case 6:    fill(270)
        case 7:    fill(315)
        default:   fill(359.99)
        }
    }

    // ── Wind barb — port of draw_barb ──────────────────────────────────
    // Half barb = 5 kt, full barb = 10 kt, pennant (triangle) = 50 kt.
    // Calm (< 1 kt): extra ring, no shaft.

    private func drawBarb(_ context: inout GraphicsContext, ink: Color, halo: Color?) {
        let knots = observation.windSpeedKnots
        let center = CGPoint(x: G.cx, y: G.cy)

        if knots < 1 {
            let ring = circlePath(center: center, radius: G.r + 8)
            if let halo {
                context.stroke(ring, with: .color(halo), lineWidth: 9)
            }
            context.stroke(ring, with: .color(ink), lineWidth: 4)
            return
        }

        let a = observation.windFromDegrees * .pi / 180   // wind blows FROM
        let ux = sin(a), uy = -cos(a)                     // outward unit vector
        let px = -uy, py = ux                             // perpendicular (barb side)

        func at(_ f: Double) -> CGPoint {                 // fraction along the shaft
            let d = G.r + G.barbLen * f
            return CGPoint(x: G.cx + ux * d, y: G.cy + uy * d)
        }

        var segs: [(a: CGPoint, b: CGPoint, w: Double)] = [(at(0), at(1), 7)]
        var pennants: [Path] = []

        var kt = Int((knots / 5).rounded()) * 5
        var t = 1.0                                       // 1 = tip, 0 = circle edge
        let step = 13.0 / G.barbLen
        let fb = 24.0, hb = 13.0                          // full / half barb length

        while kt >= 50 {                                  // pennant (filled triangle)
            let b = at(t)
            let c = at(t - step * 1.7)
            var path = Path()
            path.move(to: b)
            path.addLine(to: CGPoint(x: b.x + px * fb, y: b.y + py * fb))
            path.addLine(to: c)
            path.closeSubpath()
            pennants.append(path)
            t -= step * 2.0
            kt -= 50
        }
        while kt >= 10 {                                  // full barb
            let b = at(t)
            segs.append((b, CGPoint(x: b.x + px * fb + ux * 6, y: b.y + py * fb + uy * 6), 7))
            t -= step
            kt -= 10
        }
        if kt >= 5 {                                      // half barb
            if t > 0.85 { t -= step }                     // keep it off the very tip
            let b = at(t)
            segs.append((b, CGPoint(x: b.x + px * hb + ux * 3, y: b.y + py * hb + uy * 3), 7))
        }

        if let halo {                                     // casing underneath
            for seg in segs {
                strokeLine(&context, from: seg.a, to: seg.b, color: halo, width: seg.w + 5)
            }
            for path in pennants {
                context.fill(path, with: .color(halo))
                context.stroke(path, with: .color(halo),
                               style: StrokeStyle(lineWidth: 5, lineJoin: .round))
            }
        }
        for seg in segs {
            strokeLine(&context, from: seg.a, to: seg.b, color: ink, width: seg.w)
        }
        for path in pennants {
            context.fill(path, with: .color(ink))
        }
    }

    // ── Present weather — port of draw_precip + build_svg placement ────

    private func drawPresentWeather(_ context: inout GraphicsContext, ink: Color) {
        guard let key = observation.precip else { return }
        let color = mono ? ink : key.tint

        // Present weather stays left of the circle, but when the barb has a
        // westerly component it shares that side — nudge the glyph into the
        // opposite vertical half (build_svg's collision avoidance).
        var ay = G.cy
        let wdir = observation.windFromDegrees * .pi / 180
        if observation.windSpeedKnots >= 1 && sin(wdir) < -0.1 {
            ay = -cos(wdir) >= 0 ? G.cy - G.r * 0.7 : G.cy + G.r * 0.7
        }
        drawGlyph(&context, key: key, x: G.cx - G.r - 26, y: ay, s: 28, color: color)
    }

    private func drawGlyph(_ context: inout GraphicsContext,
                           key: StationObservation.PrecipKey,
                           x: Double, y: Double, s: Double, color: Color) {
        func dot(_ cx: Double, _ cy: Double, _ radius: Double) {
            context.fill(circlePath(center: CGPoint(x: cx, y: cy), radius: radius),
                         with: .color(color))
        }
        func glyphLine(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
            strokeLine(&context, from: CGPoint(x: x1, y: y1),
                       to: CGPoint(x: x2, y: y2), color: color, width: 4)
        }
        func star(_ sx: Double, _ sy: Double, _ ss: Double) {
            for i in 0..<3 {
                let ang = Double(i) * 60 * .pi / 180
                let dx = cos(ang) * ss * 0.5, dy = sin(ang) * ss * 0.5
                glyphLine(sx - dx, sy - dy, sx + dx, sy + dy)
            }
        }
        func shower(_ sx: Double, _ sy: Double, _ ss: Double) {
            var path = Path()
            path.move(to: CGPoint(x: sx, y: sy - ss * 0.5))
            path.addLine(to: CGPoint(x: sx - ss * 0.45, y: sy + ss * 0.4))
            path.addLine(to: CGPoint(x: sx + ss * 0.45, y: sy + ss * 0.4))
            path.closeSubpath()
            context.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: 4, lineJoin: .round))
        }

        switch key {
        case .drizzle:
            // Comma: round head, tail seamless with the head's right curve.
            dot(x, y - s * 0.16, s * 0.40)
            var tail = Path()
            tail.move(to: CGPoint(x: x + s * 0.360, y: y + s * 0.016))
            tail.addCurve(to: CGPoint(x: x + s * 0.00, y: y + s * 0.88),
                          control1: CGPoint(x: x + s * 0.52, y: y + s * 0.50),
                          control2: CGPoint(x: x + s * 0.26, y: y + s * 0.92))
            tail.addCurve(to: CGPoint(x: x - s * 0.19, y: y + s * 0.13),
                          control1: CGPoint(x: x + s * 0.00, y: y + s * 0.44),
                          control2: CGPoint(x: x - s * 0.096, y: y + s * 0.232))
            tail.closeSubpath()
            context.fill(tail, with: .color(color))
        case .rain:
            dot(x, y, s * 0.5)
        case .heavyRain:
            let r = s * 0.32, g = s * 0.42
            dot(x, y - g, r)
            dot(x - g, y + g * 0.6, r)
            dot(x + g, y + g * 0.6, r)
        case .snow:
            star(x, y, s)
        case .sleet:
            dot(x, y - s * 0.45, s * 0.22)
            star(x, y + s * 0.3, s * 0.8)
        case .snowShower:
            star(x, y - s * 0.4, s * 0.8)
            shower(x, y + s * 0.5, s * 0.8)
        case .thunder:
            var bolt = Path()
            bolt.move(to: CGPoint(x: x + s * 0.18, y: y - s * 0.55))
            bolt.addLine(to: CGPoint(x: x - s * 0.30, y: y + s * 0.10))
            bolt.addLine(to: CGPoint(x: x - s * 0.02, y: y + s * 0.05))
            bolt.addLine(to: CGPoint(x: x - s * 0.20, y: y + s * 0.55))
            bolt.addLine(to: CGPoint(x: x + s * 0.34, y: y - s * 0.12))
            bolt.addLine(to: CGPoint(x: x + s * 0.04, y: y - s * 0.06))
            bolt.closeSubpath()
            context.fill(bolt, with: .color(color))
        case .mist:
            for t in [-0.18, 0.18] {
                glyphLine(x - s * 0.5, y + s * t, x + s * 0.5, y + s * t)
            }
        case .fog:
            for t in [-0.3, 0.0, 0.3] {
                glyphLine(x - s * 0.5, y + s * t, x + s * 0.5, y + s * t)
            }
        }
    }
}

// ── PRECIP_TINT ────────────────────────────────────────────────────────

extension StationObservation.PrecipKey {
    var tint: Color {
        switch self {
        case .drizzle:    Color(hex: 0x0EA5E9)
        case .rain:       Color(hex: 0x2563EB)
        case .heavyRain:  Color(hex: 0x1D4ED8)
        case .sleet:      Color(hex: 0x6366F1)
        case .snow:       Color(hex: 0x0284C7)
        case .snowShower: Color(hex: 0x0369A1)
        case .thunder:    Color(hex: 0xCA8A04)
        case .mist:       Color(hex: 0x64748B)
        case .fog:        Color(hex: 0x475569)
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

#Preview("Rain, SW 18 kn, 6/8") {
    StationPlot(observation: .sample, haloColor: Color(uiColor: .systemBackground))
        .padding(40)
}

#Preview("Overcast gale, mono") {
    var obs = StationObservation.sample
    obs.cloudCoverPercent = 100
    obs.windSpeedKnots = 55
    obs.weatherCode = 95
    return StationPlot(observation: obs, mono: true,
                       haloColor: Color(uiColor: .systemBackground))
        .padding(40)
}

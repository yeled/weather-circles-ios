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
    /// Draw the full Met Office station model around the circle: TT
    /// upper-left, TdTd lower-left, PPP upper-right, a+pp tendency at
    /// right, W₁ past weather lower-right, visibility by the ww slot.
    /// Off = the plain TRMNL circle (temperature upper-right), which is
    /// what the widgets use.
    var fullStationModel: Bool = false
    /// How PPP and pp are written: the chart's coded shorthand, or the
    /// figures in full. Only the full station model draws either, so
    /// everything else takes the default and is unaffected.
    var pressureStyle: PressureStyle = .default
    /// How TT and TdTd are written — °C (the chart's convention) or °F.
    var temperatureUnit: TemperatureUnit = .default
    /// Casing drawn under the barb so it survives a solid 8-okta disc
    /// (`halo` in the Python). Pass the view's background colour.
    var haloColor: Color?
    /// Which elements to draw. The guide's illustrations show one piece at
    /// a time; everything else draws the lot.
    var parts: Parts = .all
    /// Slot to outline — the guide's "you tapped this bit" feedback.
    var highlightedSlot: StationSlot?
    /// Set this and the plot becomes tappable: a tap reports the slot it
    /// landed on. Nil (the widgets, the forecast rows) = no gesture.
    var onSelectSlot: ((StationSlot) -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    struct Parts: OptionSet {
        let rawValue: Int
        static let oktas          = Parts(rawValue: 1 << 0)
        static let barb           = Parts(rawValue: 1 << 1)
        static let presentWeather = Parts(rawValue: 1 << 2)
        static let annotations    = Parts(rawValue: 1 << 3)
        static let temperature    = Parts(rawValue: 1 << 4)
        static let all: Parts = [.oktas, .barb, .presentWeather, .annotations, .temperature]
    }

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
            if let highlightedSlot {
                drawHighlight(&context, slot: highlightedSlot, ink: ink)
            }
            if parts.contains(.oktas) {
                drawOktas(&context, ink: ink)
            }
            if parts.contains(.barb) {
                drawBarb(&context, ink: ink, halo: haloColor)
            }
            if parts.contains(.presentWeather) {
                drawPresentWeather(&context, ink: ink)
            }
            if fullStationModel && parts.contains(.annotations) {
                drawStationModelAnnotations(&context, ink: ink)
            }
            if showTemperature && parts.contains(.temperature) {
                let label = Text("\(observation.roundedTemp(temperatureUnit))°")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(ink)
                if fullStationModel {
                    // TT — the Met Office slot, upper-left.
                    context.draw(label, at: temperatureAnchor, anchor: .bottomTrailing)
                } else {
                    // The TRMNL renderer's position, upper-right.
                    context.draw(label, at: temperatureAnchor, anchor: .bottomLeading)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(Text(observation.accessibilitySummary(temperatureUnit)))
        .accessibilityIdentifier("stationPlot")   // the screenshot UI test aims at this
        .overlay { tapTarget }
    }

    /// A transparent twin of the canvas that turns taps into slots. Kept
    /// out of the Canvas itself so the geometry maths has a size to work
    /// against without the drawing closure re-running on every touch.
    @ViewBuilder private var tapTarget: some View {
        if let onSelectSlot {
            GeometryReader { geometry in
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        if let slot = slot(at: location, in: geometry.size) {
                            onSelectSlot(slot)
                        }
                    }
            }
            .accessibilityHidden(true)      // the guide list is the VoiceOver route
        }
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

    // ── Tappable slots ─────────────────────────────────────────────────

    private struct SlotRegion {
        var slot: StationSlot
        var rect: CGRect
    }

    /// Where each drawn element sits, in SVG user units — the tap targets
    /// and the highlight boxes, derived from the same anchors the drawing
    /// code uses so the two can't drift.
    private var slotRegions: [SlotRegion] {
        func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
            CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)
        }
        var regions: [SlotRegion] = []

        if parts.contains(.barb) {
            if observation.windSpeedKnots < 1 {          // the calm ring
                let d = (G.r + 16) * 2
                regions.append(.init(slot: .wind, rect: box(G.cx, G.cy, d, d)))
            } else {
                let a = observation.windFromDegrees * .pi / 180
                let ux = sin(a), uy = -cos(a)
                let tip = CGPoint(x: G.cx + ux * (G.r + G.barbLen),
                                  y: G.cy + uy * (G.r + G.barbLen))
                let root = CGPoint(x: G.cx + ux * G.r, y: G.cy + uy * G.r)
                let shaft = CGRect(x: min(root.x, tip.x), y: min(root.y, tip.y),
                                   width: abs(tip.x - root.x),
                                   height: abs(tip.y - root.y))
                regions.append(.init(slot: .wind, rect: shaft.insetBy(dx: -18, dy: -18)))
            }
        }
        if parts.contains(.presentWeather), observation.effectivePrecip != nil {
            regions.append(.init(slot: .presentWeather,
                                 rect: box(G.cx - G.r - 26, presentWeatherAnchorY, 44, 44)))
        }
        if parts.contains(.temperature), showTemperature {
            let dx = fullStationModel ? -23.0 : 23.0
            regions.append(.init(slot: .temperature,
                                 rect: box(temperatureAnchor.x + dx, temperatureAnchor.y - 15, 50, 34)))
        }
        if fullStationModel && parts.contains(.annotations) {
            if observation.dewPointRounded != nil {
                regions.append(.init(slot: .dewPoint,
                                     rect: box(dewPointAnchor.x - 23, dewPointAnchor.y + 15, 50, 34)))
            }
            if observation.pressureText(pressureStyle) != nil {
                let w = pressureLabelWidth
                regions.append(.init(slot: .pressure,
                                     rect: box(pressureAnchor.x + w / 2 - 1, pressureAnchor.y - 15, w, 34)))
            }
            if observation.pressureChangeText(pressureStyle) != nil,
               observation.pressureTendency != nil {
                regions.append(.init(slot: .tendency,
                                     rect: box(G.cx + G.r + 34, tendencyAnchorY, 60, 32)))
            }
            if observation.pastWeather != nil {
                regions.append(.init(slot: .pastWeather,
                                     rect: box(pastWeatherAnchor.x, pastWeatherAnchor.y, 36, 36)))
            }
            if observation.visibilityText != nil {
                regions.append(.init(slot: .visibility,
                                     rect: box(G.cx - G.r - 40, presentWeatherAnchorY - 26, 44, 20)))
            }
            if observation.lowCloudGenus != nil {
                let base = lowCloudGenusBase
                regions.append(.init(slot: .cloudGenus,
                                     rect: box(base.x, base.y - 10, 36, 36)))
            }
        }
        if parts.contains(.oktas) {                      // the backstop
            let d = (G.r + G.stroke / 2) * 2
            regions.append(.init(slot: .cloud, rect: box(G.cx, G.cy, d, d)))
        }
        return regions
    }

    /// The slot under a tap given in the view's own coordinates. Smallest
    /// box wins where the annotations crowd each other; the circle is
    /// always last, so a barb rooted on the rim still beats it.
    func slot(at point: CGPoint, in size: CGSize) -> StationSlot? {
        let scale = min(size.width, size.height) / G.size
        guard scale > 0 else { return nil }
        let local = CGPoint(x: (point.x - (size.width - G.size * scale) / 2) / scale,
                            y: (point.y - (size.height - G.size * scale) / 2) / scale)
        let hits = slotRegions.filter { $0.rect.contains(local) }
        let annotated = hits.filter { $0.slot != .cloud }
            .min { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }
        return (annotated ?? hits.first { $0.slot == .cloud })?.slot
    }

    /// Ink, not an accent: nothing else in the app is coloured, and a grey
    /// box reads as part of the chart rather than as chrome.
    ///
    /// Kept inside the 260-unit box: the Canvas clips to its own bounds,
    /// and the slots that sit hard against the rim (the barb, VV, a+pp)
    /// otherwise push their padded box past the edge and lose that side's
    /// border. Clamping keeps the outline closed — every one of those
    /// boxes still contains its glyph with room to spare, because it's
    /// only the padding that overflows, never the mark itself.
    private func drawHighlight(_ context: inout GraphicsContext,
                               slot: StationSlot, ink: Color) {
        guard let region = slotRegions.first(where: { $0.slot == slot }) else { return }
        let inset = 2.0                   // ≥ half the stroke, so it stays whole
        let bounds = CGRect(x: inset, y: inset,
                            width: G.size - inset * 2, height: G.size - inset * 2)
        let rect = region.rect.insetBy(dx: -7, dy: -7).intersection(bounds)
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return }
        let path = Path(roundedRect: rect, cornerRadius: 18)
        context.fill(path, with: .color(ink.opacity(0.10)))
        context.stroke(path, with: .color(ink.opacity(0.35)), lineWidth: 2.5)
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

    /// Vertical anchor for the ww glyph: left of the circle, nudged into
    /// the opposite vertical half when the barb has a westerly component
    /// (build_svg's collision avoidance).
    private var presentWeatherAnchorY: Double {
        let wdir = observation.windFromDegrees * .pi / 180
        if observation.windSpeedKnots >= 1 && sin(wdir) < -0.1 {
            return -cos(wdir) >= 0 ? G.cy - G.r * 0.7 : G.cy + G.r * 0.7
        }
        return G.cy
    }

    /// The a+pp row's vertical anchor — the mirror of the ww rule, nudged
    /// off an easterly barb.
    private var tendencyAnchorY: Double {
        let wdir = observation.windFromDegrees * .pi / 180
        if observation.windSpeedKnots >= 1 && sin(wdir) > 0.1 {
            return -cos(wdir) >= 0 ? G.cy - G.r * 0.7 : G.cy + G.r * 0.7
        }
        return G.cy
    }

    /// C_L's base line: below the circle, or on W₁'s mirror diagonal when
    /// a southerly barb owns bottom-centre.
    private var lowCloudGenusBase: CGPoint {
        let wdir = observation.windFromDegrees * .pi / 180
        if observation.windSpeedKnots >= 1 && -cos(wdir) > 0.8 {
            return CGPoint(x: G.cx - (G.r + 30) * 0.7071,
                           y: G.cy + (G.r + 30) * 0.7071)
        }
        return CGPoint(x: G.cx, y: G.cy + G.r + 34)
    }

    /// Sidesteps a corner slot out of the barb's path. TT, TdTd, PPP and
    /// W₁ each sit in a fixed diagonal (NW/SW/NE/SE), and the barb's shaft
    /// is drawn full-length regardless of speed — so whenever the wind
    /// happens to come from roughly that same diagonal, the two used to
    /// sit right on top of each other (ww/pp/genus already dodge this by
    /// swapping to the opposite vertical half; the corners have no such
    /// spare slot, so instead they slide sideways, perpendicular to the
    /// shaft, just far enough to clear it).
    private func clearBarb(_ anchor: CGPoint) -> CGPoint {
        guard parts.contains(.barb), observation.windSpeedKnots >= 1 else { return anchor }
        let a = observation.windFromDegrees * .pi / 180
        let ux = sin(a), uy = -cos(a)
        let vx = anchor.x - G.cx, vy = anchor.y - G.cy
        let along = vx * ux + vy * uy         // distance out along the shaft
        guard along > 0, along < G.r + G.barbLen + 20 else { return anchor }
        let perpX = vx - along * ux, perpY = vy - along * uy
        let clearance = 40.0                  // half label width + half barb width, plus margin
        let dist = (perpX * perpX + perpY * perpY).squareRoot()
        guard dist < clearance else { return anchor }
        let (nx, ny) = dist > 0.01 ? (perpX / dist, perpY / dist) : (-uy, ux)
        let push = clearance - dist
        return CGPoint(x: anchor.x + nx * push, y: anchor.y + ny * push)
    }

    /// TT's anchor: upper-left in the full model (upper-right in the
    /// plain TRMNL circle), nudged clear of a NW-ish barb.
    private var temperatureAnchor: CGPoint {
        clearBarb(fullStationModel
            ? CGPoint(x: G.cx - G.r * 0.5, y: G.cy - G.r - 6)
            : CGPoint(x: G.cx + G.r * 0.5, y: G.cy - G.r - 6))
    }

    /// TdTd's anchor: lower-left, nudged clear of a SW-ish barb.
    private var dewPointAnchor: CGPoint {
        clearBarb(CGPoint(x: G.cx - G.r * 0.5, y: G.cy + G.r + 6))
    }

    /// PPP's anchor: upper-right, nudged clear of a NE-ish barb — then
    /// held back from the right edge by the width of the label it carries.
    /// A code is three characters and always fitted; `1021.6` is six, and
    /// a barb nudge (up to 40 units) would push it off the plate, where
    /// the Canvas would clip it.
    private var pressureAnchor: CGPoint {
        let anchor = clearBarb(CGPoint(x: G.cx + G.r * 0.5, y: G.cy - G.r - 6))
        return CGPoint(x: min(anchor.x, G.size - pressureLabelWidth), y: anchor.y)
    }

    /// PPP's type size and the room it needs. The spelled-out figure is
    /// twice as many characters as the code, so it gives up a few points
    /// rather than crowd the circle.
    private var pressureLabelSize: Double { pressureStyle == .coded ? 26 : 20 }
    private var pressureLabelWidth: Double { pressureStyle == .coded ? 54 : 68 }

    /// pp's type size. There are 58 units between the rim and the right
    /// edge for the figure, the trace glyph and the gap: `+11` fits at 18,
    /// `+1.1` only at 14.
    private var tendencyLabelSize: Double { pressureStyle == .coded ? 18 : 14 }

    /// W₁'s anchor: lower-right diagonal, nudged clear of a SE-ish barb.
    private var pastWeatherAnchor: CGPoint {
        clearBarb(CGPoint(x: G.cx + (G.r + 30) * 0.7071, y: G.cy + (G.r + 30) * 0.7071))
    }

    private func drawPresentWeather(_ context: inout GraphicsContext, ink: Color) {
        guard let key = observation.effectivePrecip else { return }
        let color = mono ? ink : key.tint
        drawGlyph(&context, key: key, x: G.cx - G.r - 26, y: presentWeatherAnchorY,
                  s: 28, color: color)
    }

    // ── Met Office station-model slots (full model only) ───────────────

    private func drawStationModelAnnotations(_ context: inout GraphicsContext, ink: Color) {
        func label(_ string: String, size: Double, weight: Font.Weight = .bold) -> Text {
            Text(string).font(.system(size: size, weight: weight)).foregroundStyle(ink)
        }

        // TdTd — dew point, lower-left.
        if let dew = observation.dewPointRounded(temperatureUnit) {
            context.draw(label("\(dew)°", size: 26), at: dewPointAnchor, anchor: .topTrailing)
        }
        // PPP — MSLP upper-right, coded in tenths or written in full.
        if let ppp = observation.pressureText(pressureStyle) {
            context.draw(label(ppp, size: pressureLabelSize),
                         at: pressureAnchor, anchor: .bottomLeading)
        }
        // a + pp — 3-hour tendency at 3 o'clock, nudged off an easterly
        // barb (mirror of the ww rule).
        if let pp = observation.pressureChangeText(pressureStyle),
           let tendency = observation.pressureTendency {
            let y = tendencyAnchorY
            context.draw(label(pp, size: tendencyLabelSize, weight: .semibold),
                         at: CGPoint(x: G.cx + G.r + 8, y: y), anchor: .leading)
            drawTendencyGlyph(&context, tendency,
                              at: CGPoint(x: G.cx + G.r + 42, y: y), ink: ink)
        }
        // W₁ — most significant past weather, small, lower-right.
        if let past = observation.pastWeather {
            drawGlyph(&context, key: past,
                      x: pastWeatherAnchor.x, y: pastWeatherAnchor.y,
                      s: 18, color: ink)
        }
        // VV — visibility, just above the ww slot (shown in km — a small
        // liberty vs the coded synoptic figure).
        if let visibility = observation.visibilityText {
            context.draw(label(visibility, size: 12, weight: .medium),
                         at: CGPoint(x: G.cx - G.r - 22, y: presentWeatherAnchorY - 26),
                         anchor: .trailing)
        }
        // C_L — observed convective low-cloud genus (nearest METAR),
        // below the circle. When a southerly barb owns bottom-centre,
        // it moves to the lower-left diagonal — W₁'s mirror slot.
        if let genus = observation.lowCloudGenus {
            drawGenusGlyph(&context, genus, at: lowCloudGenusBase, ink: ink)
        }
    }

    /// WMO C_L glyphs: 2 (towering cumulus — tall dome on a base line)
    /// and 9 (cumulonimbus — tower with the anvil top).
    private func drawGenusGlyph(_ context: inout GraphicsContext,
                                _ genus: StationObservation.LowCloudGenus,
                                at base: CGPoint, ink: Color) {
        var path = Path()
        path.move(to: CGPoint(x: base.x - 11, y: base.y))
        path.addLine(to: CGPoint(x: base.x + 11, y: base.y))
        switch genus {
        case .toweringCumulus:
            path.move(to: CGPoint(x: base.x - 8, y: base.y))
            path.addCurve(to: CGPoint(x: base.x + 8, y: base.y),
                          control1: CGPoint(x: base.x - 10, y: base.y - 24),
                          control2: CGPoint(x: base.x + 10, y: base.y - 24))
        case .cumulonimbus:
            path.move(to: CGPoint(x: base.x - 7, y: base.y))
            path.addLine(to: CGPoint(x: base.x - 4, y: base.y - 16))
            path.move(to: CGPoint(x: base.x + 7, y: base.y))
            path.addLine(to: CGPoint(x: base.x + 4, y: base.y - 16))
            path.move(to: CGPoint(x: base.x - 12, y: base.y - 16))
            path.addLine(to: CGPoint(x: base.x + 12, y: base.y - 16))
        }
        context.stroke(path, with: .color(ink),
                       style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
    }

    /// The WMO "a" barograph-trace shapes, as small polylines.
    private func drawTendencyGlyph(_ context: inout GraphicsContext,
                                   _ tendency: StationObservation.PressureTendency,
                                   at origin: CGPoint, ink: Color) {
        let w = 18.0, h = 14.0
        let points: [(Double, Double)]
        switch tendency {
        case .rising:         points = [(0, h / 2), (w, -h / 2)]
        case .falling:        points = [(0, -h / 2), (w, h / 2)]
        case .steady:         points = [(0, 0), (w, 0)]
        case .riseThenFall:   points = [(0, h / 2), (w * 0.55, -h / 2), (w, -h * 0.07)]
        case .fallThenRise:   points = [(0, -h / 2), (w * 0.55, h / 2), (w, h * 0.07)]
        case .steadyThenRise: points = [(0, h * 0.35), (w * 0.5, h * 0.35), (w, -h / 2)]
        case .steadyThenFall: points = [(0, -h * 0.35), (w * 0.5, -h * 0.35), (w, h / 2)]
        }
        var path = Path()
        path.move(to: CGPoint(x: origin.x + points[0].0, y: origin.y + points[0].1))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: origin.x + point.0, y: origin.y + point.1))
        }
        context.stroke(path, with: .color(ink),
                       style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
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

#Preview("Full station model — rain, SW 18 kn, 6/8") {
    StationPlot(observation: .sample, fullStationModel: true,
                haloColor: Color(uiColor: .systemBackground))
        .padding(40)
}

#Preview("Full station model — pressure written out") {
    StationPlot(observation: .sample, fullStationModel: true,
                pressureStyle: .hectopascals,
                haloColor: Color(uiColor: .systemBackground))
        .padding(40)
}

#Preview("Repo circle (widget style)") {
    StationPlot(observation: .sample, haloColor: Color(uiColor: .systemBackground))
        .padding(40)
}

#Preview("Cb observed — storm day") {
    var obs = StationObservation.sample
    obs.weatherCode = 95
    obs.lowCloudGenus = .cumulonimbus
    obs.genusStationICAO = "EGLL"
    return StationPlot(observation: obs, fullStationModel: true,
                       haloColor: Color(uiColor: .systemBackground))
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

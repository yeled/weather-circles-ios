import SwiftUI

/// The area chart: the outline of the country you're in, with a circle on
/// each of its major cities.
///
/// Deliberately loose. The coastline comes from a bundled 1:50m Natural
/// Earth trace rounded to about a kilometre, and the points are cities
/// rather than a lattice — a scatter of real places reads as a weather
/// chart, where a perfect grid reads as a model dump. Everything is drawn
/// in the app's one ink colour, same as every other circle it draws.
struct CountryChartView: View {
    var centerLatitude: Double
    var centerLongitude: Double
    var placeName: String
    /// The page is off-screen until it's paged to; the fetch waits for it.
    var isActive: Bool

    @AppStorage(TemperatureUnitStore.key, store: TemperatureUnitStore.defaults)
    private var temperatureUnit: TemperatureUnit = .default

    @State private var region: CountryAtlas.Region?
    @State private var readings: [AreaObservationsClient.Reading] = []
    @State private var fetchedAt: Date?
    @State private var errorText: String?
    @State private var isLoading = false
    @State private var loadedKey: String?

    /// How many circles the chart carries. Enough to show a front crossing
    /// the country, few enough that they don't collide.
    private static let maxPoints = 12
    /// Minimum gap between two circles, as a fraction of the chart's own
    /// width — so the spacing holds whether it's Belgium or Brazil. Tuned
    /// on Britain: much above this and the Midlands swallow the north.
    private static let minSeparation = 0.085
    /// How much chart a single circle is taken to speak for. Land further
    /// than this from every chosen point gets one of its own.
    private static let coverageRadius = 0.24

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.compact.up")
                Text("7 days")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            Text(region?.name ?? placeName)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            chart
            footer
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .task(id: fetchKey) { await load() }
    }

    private var subtitle: String {
        if let errorText { return errorText }
        if readings.isEmpty { return isLoading ? "Plotting…" : "Nothing to plot here" }
        return "\(readings.count) places, now"
    }

    // ── The chart ──────────────────────────────────────────────────────

    private var chart: some View {
        GeometryReader { proxy in
            let projection = region.map {
                Projection(region: $0, size: proxy.size, inset: 28)
            }
            ZStack {
                if let region, let projection {
                    Canvas { context, _ in
                        var path = Path()
                        for ring in region.rings {
                            guard ring.count > 2 else { continue }
                            path.move(to: projection.point(latitude: ring[0].y,
                                                           longitude: ring[0].x))
                            for vertex in ring.dropFirst() {
                                path.addLine(to: projection.point(latitude: vertex.y,
                                                                  longitude: vertex.x))
                            }
                            path.closeSubpath()
                        }
                        // A whisper of tone so land reads as land, then the
                        // coastline itself.
                        context.fill(path, with: .color(.primary.opacity(0.06)))
                        context.stroke(path, with: .color(.primary.opacity(0.55)),
                                       style: StrokeStyle(lineWidth: 1, lineJoin: .round))
                    }
                    .accessibilityHidden(true)

                    // Circles first, names second: a name that lands under
                    // a neighbour's circle would otherwise be swallowed by
                    // an 8-okta disc, and every chart has crowded corners.
                    let placed = readings.map {
                        ($0, projection.point(latitude: $0.latitude, longitude: $0.longitude))
                    }
                    let metrics = Metrics(plate: proxy.size)
                    ForEach(placed, id: \.0.id) { reading, point in
                        StationPlot(observation: reading.observation,
                                    mono: true,       // black and white, like the rest
                                    showTemperature: false,
                                    haloColor: Color(uiColor: .systemBackground))
                            .frame(width: metrics.circle, height: metrics.circle)
                            .accessibilityHidden(true)
                            .position(point)
                    }
                    let names = Self.nameLayout(for: placed, in: proxy.size,
                                                metrics: metrics,
                                                unit: temperatureUnit)
                    ForEach(placed, id: \.0.id) { reading, _ in
                        if let placement = names[reading.id] {
                            label(for: reading, compact: placement.compact,
                                  metrics: metrics)
                                .position(placement.at)
                        }
                    }
                    scaleBar(kmPerPoint: projection.kmPerPoint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .bottomLeading)
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: Self.maxPlateWidth, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
    }

    /// The chart gets more room than the rest of the app: the main page is
    /// capped at 560 so a single circle doesn't become a dinner plate on an
    /// iPad, but a chart of a country wants the width — at 560 it sat in a
    /// column down the middle with half the iPad empty either side.
    static let maxPlateWidth = 820.0

    /// How big the marks are drawn, which scales with the plate rather
    /// than sitting fixed: a 52-point circle is right on a phone and lost
    /// on an iPad. Sub-linear, so the circles don't swallow the country.
    struct Metrics {
        var circle: Double
        var textStyle: UIFont.TextStyle
        var font: Font

        init(plate: CGSize) {
            let width = max(plate.width, 1)
            circle = min(78, max(46, 38 + width * 0.035))
            let wide = width > 620
            textStyle = wide ? .footnote : .caption2
            font = wide ? .footnote : .caption2
        }
    }

    /// A place's name and temperature. Where you are is in full ink; the
    /// rest are secondary, so the chart still says where you're standing.
    private func label(for reading: AreaObservationsClient.Reading,
                       compact: Bool, metrics: Metrics) -> some View {
        HStack(spacing: 3) {
            if !compact, !reading.name.isEmpty {   // scattered filler points have none
                Text(reading.name)
                    .foregroundStyle(reading.id == 0 ? .primary : .secondary)
            }
            Text("\(reading.observation.roundedTemp(temperatureUnit))°")
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(metrics.font)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 2)
        .background(Color(uiColor: .systemBackground).opacity(0.85))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(reading.name): \(reading.observation.accessibilitySummary(temperatureUnit))"))
    }

    /// Where every name goes, in one pass over the chart.
    ///
    /// A name is much wider than its circle, so keeping the circles apart
    /// isn't enough to keep the names apart: on a small crowded country
    /// (Denmark) two places a comfortable 40 km apart still had "Roskilde"
    /// printed across "Copenhagen". Each name takes the first free slot —
    /// under its circle, over it, then beside it — measured against every
    /// circle on the chart and every name already placed. Whoever comes
    /// first wins the good slot, and the order is where you are, then the
    /// cities by size, so the least important name is the one that ends up
    /// somewhere odd.
    struct NamePlacement: Equatable {
        var at: CGPoint
        /// Nothing the full name would fit in: show the temperature alone.
        var compact: Bool
    }

    static func nameLayout(for placed: [(AreaObservationsClient.Reading, CGPoint)],
                           in size: CGSize, metrics: Metrics,
                           unit: TemperatureUnit) -> [Int: NamePlacement] {
        let circle = metrics.circle
        let circles = placed.map { CGRect(x: $0.1.x - circle / 2, y: $0.1.y - circle / 2,
                                          width: circle, height: circle) }
        var taken: [CGRect] = []
        var layout: [Int: NamePlacement] = [:]

        for (reading, point) in placed {
            var best: (rect: CGRect, compact: Bool, overlap: Double)?
            // Full name first; if the chart is too crowded for it anywhere
            // — Zealand, with four places inside 60 km — the temperature on
            // its own is a third of the width and nearly always fits.
            for compact in [false, true] {
                let label = Self.measure(reading, compact: compact, metrics: metrics,
                                         unit: unit)
                guard label.width <= size.width, label.height <= size.height else { continue }
                for candidate in slots(around: point, label: label, circle: circle) {
                    // Slid back inside the chart rather than rejected: a
                    // place near the edge (Copenhagen is 20 km from the
                    // right-hand margin) would otherwise lose its name to
                    // the compact fallback for want of a few points.
                    let rect = CGRect(
                        x: min(max(0, candidate.x - label.width / 2), size.width - label.width),
                        y: min(max(0, candidate.y - label.height / 2), size.height - label.height),
                        width: label.width, height: label.height)
                    let overlap = (circles + taken).reduce(0.0) {
                        let hit = $1.intersection(rect)
                        return $0 + (hit.isNull ? 0 : Double(hit.width * hit.height))
                    }
                    if overlap < (best?.overlap ?? .greatestFiniteMagnitude) {
                        best = (rect, compact, overlap)
                    }
                    if overlap == 0 { break }
                }
                if best?.overlap == 0 { break }
            }
            guard let best else { continue }
            taken.append(best.rect)
            layout[reading.id] = NamePlacement(at: CGPoint(x: best.rect.midX, y: best.rect.midY),
                                               compact: best.compact)
        }
        return layout
    }

    /// Slots to try, in preference order: under the circle, over it,
    /// beside it, then shouldered off to one side.
    private static func slots(around point: CGPoint, label: CGSize,
                              circle: Double) -> [CGPoint] {
        let gapX = circle / 2 + label.width / 2 + 4
        let gapY = circle / 2 + label.height / 2 + 3
        return [
            CGPoint(x: point.x, y: point.y + gapY),
            CGPoint(x: point.x, y: point.y - gapY),
            CGPoint(x: point.x + gapX, y: point.y),
            CGPoint(x: point.x - gapX, y: point.y),
            CGPoint(x: point.x + label.width / 2, y: point.y + gapY),
            CGPoint(x: point.x - label.width / 2, y: point.y + gapY),
            CGPoint(x: point.x + label.width / 2, y: point.y - gapY),
            CGPoint(x: point.x - label.width / 2, y: point.y - gapY),
            CGPoint(x: point.x, y: point.y + gapY * 1.8),
            CGPoint(x: point.x, y: point.y - gapY * 1.8),
        ]
    }

    /// The name's size on screen, so the layout above can reason about it
    /// before SwiftUI has drawn anything. Measured in the same text style
    /// the label uses, so it follows Dynamic Type too.
    private static func measure(_ reading: AreaObservationsClient.Reading,
                                compact: Bool, metrics: Metrics,
                                unit: TemperatureUnit) -> CGSize {
        let degrees = "\(reading.observation.roundedTemp(unit))°"
        let text = (compact || reading.name.isEmpty) ? degrees : "\(reading.name) \(degrees)"
        let font = UIFont.preferredFont(forTextStyle: metrics.textStyle)
        let size = (text as NSString).size(withAttributes: [.font: font])
        return CGSize(width: size.width.rounded(.up) + 10,   // padding + the bold degrees
                      height: size.height.rounded(.up) + 2)
    }

    private func scaleBar(kmPerPoint: Double) -> some View {
        let km = scaleLengthKM(kmPerPoint: kmPerPoint)
        return VStack(alignment: .leading, spacing: 2) {
            Rectangle()
                .frame(width: km / max(kmPerPoint, 0.0001), height: 1)
            Text("\(Int(km)) km")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.secondary)
    }

    /// A round number that lands somewhere near a fifth of the chart.
    private func scaleLengthKM(kmPerPoint: Double) -> Double {
        let target = kmPerPoint * 90
        let steps: [Double] = [10, 25, 50, 100, 200, 250, 500, 1000, 2000]
        return steps.last { $0 <= target } ?? steps[0]
    }

    private var footer: some View {
        Group {
            if let fetchedAt {
                Text("Updated \(fetchedAt.formatted(date: .omitted, time: .shortened)) · cloud, wind and weather at each place")
            } else {
                Text("Cloud, wind and weather at each place")
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .multilineTextAlignment(.center)
    }

    // ── Loading ────────────────────────────────────────────────────────

    private var fetchKey: String {
        String(format: "%@-%.2f-%.2f", isActive ? "on" : "off",
               centerLatitude, centerLongitude)
    }

    private func load() async {
        guard isActive, fetchKey != loadedKey else { return }
        isLoading = true
        defer { isLoading = false }

        // The first call parses the whole atlas — off the main actor.
        let latitude = centerLatitude, longitude = centerLongitude
        let found = await Task.detached(priority: .userInitiated) {
            CountryAtlas.region(latitude: latitude, longitude: longitude)
        }.value
        guard !Task.isCancelled else { return }
        guard let found else {
            region = nil
            readings = []
            errorText = "No coastline for this spot"
            return
        }
        region = found

        let points = Self.points(in: found, homeName: placeName,
                                 homeLatitude: latitude, homeLongitude: longitude)
        do {
            readings = try await AreaObservationsClient.fetch(points: points)
            fetchedAt = Date()
            errorText = nil
            loadedKey = fetchKey
        } catch is CancellationError {
            // Superseded — a new centre owns the chart now.
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            errorText = "Chart failed: \(error.localizedDescription)"
        }
    }

    /// Where you are, then the biggest cities that aren't too close to
    /// something already picked. Chosen in degrees rather than points so
    /// the selection doesn't change with the size of the view — the fetch
    /// has to be settled before there's a layout to measure.
    static func points(in region: CountryAtlas.Region, homeName: String,
                       homeLatitude: Double, homeLongitude: Double)
        -> [AreaObservationsClient.Point] {
        let shrink = max(0.15, cos(region.centerLatitude * .pi / 180))
        let width = max(region.spanLongitude * shrink, region.spanLatitude)
        let gap = width * minSeparation

        // "—" is the header's stand-in while a place name is still being
        // looked up; on the chart it would print as a name of its own.
        var chosen = [AreaObservationsClient.Point(name: homeName == "—" ? "" : homeName,
                                                   latitude: homeLatitude,
                                                   longitude: homeLongitude)]
        func clear(latitude: Double, longitude: Double) -> Bool {
            chosen.allSatisfy { picked in
                let dx = (longitude - picked.longitude) * shrink
                let dy = latitude - picked.latitude
                return (dx * dx + dy * dy).squareRoot() >= gap
            }
        }

        for city in region.cities.sorted(by: { $0.population > $1.population }) {
            guard chosen.count < maxPoints else { break }
            if clear(latitude: city.latitude, longitude: city.longitude) {
                chosen.append(.init(name: city.name,
                                    latitude: city.latitude,
                                    longitude: city.longitude))
            }
        }

        // Population alone hugs the coast: Australia comes out as nine
        // seaside cities and a blank middle, which is the part of the
        // country a weather chart most wants a reading from. So sweep a
        // staggered lattice over the land and, wherever a cell is a long
        // way from everything picked so far, pull in the biggest place
        // near it — Alice Springs, Kalgoorlie — or plot the bare spot if
        // the country has nothing listed there at all (Alaska, Greenland).
        let coverage = width * coverageRadius
        let rows = 5, columns = 5
        for row in 0..<rows {
            for column in 0..<columns {
                guard chosen.count < maxPoints else { break }
                let stagger = row.isMultiple(of: 2) ? 0.0 : 0.5
                let latitude = region.minLatitude
                    + (Double(row) + 0.5) / Double(rows) * region.spanLatitude
                let longitude = region.minLongitude
                    + (Double(column) + 0.5 + stagger) / Double(columns) * region.spanLongitude
                guard region.containsLand(latitude: latitude, longitude: longitude) else { continue }
                let uncovered = chosen.allSatisfy { picked in
                    let dx = (longitude - picked.longitude) * shrink
                    let dy = latitude - picked.latitude
                    return (dx * dx + dy * dy).squareRoot() >= coverage
                }
                guard uncovered else { continue }

                let nearby = region.cities.filter { city in
                    let dx = (city.longitude - longitude) * shrink
                    let dy = city.latitude - latitude
                    return (dx * dx + dy * dy).squareRoot() < coverage
                        && clear(latitude: city.latitude, longitude: city.longitude)
                }
                if let city = nearby.max(by: { $0.population < $1.population }) {
                    chosen.append(.init(name: city.name,
                                        latitude: city.latitude,
                                        longitude: city.longitude))
                } else if clear(latitude: latitude, longitude: longitude) {
                    chosen.append(.init(name: "", latitude: latitude, longitude: longitude))
                }
            }
        }
        return chosen
    }
}

/// Equirectangular, north up: longitudes squeezed by the cosine of the
/// chart's middle latitude, then the whole box scaled to fit. Fine for one
/// country — anything fancier would be invisible at this size.
private struct Projection {
    private let scale: Double
    private let cosLatitude: Double
    private let originX: Double
    private let originY: Double
    private let maxLatitude: Double
    private let minLongitude: Double

    init(region: CountryAtlas.Region, size: CGSize, inset: Double) {
        cosLatitude = max(0.15, cos(region.centerLatitude * .pi / 180))
        maxLatitude = region.maxLatitude
        minLongitude = region.minLongitude
        let spanX = max(region.spanLongitude * cosLatitude, 0.0001)
        let spanY = max(region.spanLatitude, 0.0001)
        let usableWidth = max(size.width - inset * 2, 1)
        let usableHeight = max(size.height - inset * 2, 1)
        scale = min(usableWidth / spanX, usableHeight / spanY)
        originX = (size.width - spanX * scale) / 2
        originY = (size.height - spanY * scale) / 2
    }

    func point(latitude: Double, longitude: Double) -> CGPoint {
        CGPoint(x: originX + (longitude - minLongitude) * cosLatitude * scale,
                y: originY + (maxLatitude - latitude) * scale)
    }

    /// Ground distance one point of the chart covers, measured north-south.
    var kmPerPoint: Double { 111.32 / scale }
}

#Preview {
    CountryChartView(centerLatitude: 51.5074, centerLongitude: -0.1278,
                     placeName: "London", isActive: true)
}

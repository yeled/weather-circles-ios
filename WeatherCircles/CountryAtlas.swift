import Foundation
import CoreGraphics

/// The bundled outlines and city lists behind the area chart.
///
/// `Atlas.json` is built by `scripts/make_atlas.py` from Natural Earth
/// (public domain): 1:50m coastlines quantised to hundredths of a degree,
/// and the 25 biggest places per country. Deliberately coarse — the chart
/// wants a recognisable shape, not a survey — and entirely offline, so no
/// boundary service has to be reachable for the page to draw.
enum CountryAtlas {
    struct Place: Equatable {
        var name: String
        var latitude: Double
        var longitude: Double
        var population: Int
        var isCapital: Bool
    }

    /// One landmass worth of country: the rings to draw, the cities on it,
    /// and the box they all fit in.
    struct Region: Equatable {
        var code: String
        var name: String
        /// Rings in degrees, as (x: longitude, y: latitude).
        var rings: [[CGPoint]]
        var cities: [Place]
        var minLongitude: Double
        var maxLongitude: Double
        var minLatitude: Double
        var maxLatitude: Double

        var centerLatitude: Double { (minLatitude + maxLatitude) / 2 }
        var spanLatitude: Double { maxLatitude - minLatitude }
        var spanLongitude: Double { maxLongitude - minLongitude }

        /// Is this point on the land the chart is drawing?
        func containsLand(latitude: Double, longitude: Double) -> Bool {
            let point = CGPoint(x: longitude, y: latitude)
            return rings.contains { CountryAtlas.contains($0, point) }
        }
    }

    /// The country containing the point, reduced to the landmass it sits on.
    ///
    /// Only the rings near that landmass come back: France's chart should
    /// be France, not a box wide enough to hold Guyane as well. Runs off
    /// the main actor — the first call parses the whole file.
    static func region(latitude: Double, longitude: Double) -> Region? {
        guard let atlas else { return nil }
        let point = CGPoint(x: longitude, y: latitude)

        // The country whose coastline actually encloses the point, else the
        // nearest one — 1:50m coastlines cut corners, and a seaside town can
        // easily land a few kilometres offshore of its own country.
        var home: (country: Country, ring: [CGPoint])?
        var nearest: (country: Country, ring: [CGPoint], distance: Double)?
        for country in atlas.countries.values {
            for ring in country.rings {
                if contains(ring, point) {
                    home = (country, ring)
                    break
                }
                let distance = squaredDistance(from: point, toVerticesOf: ring)
                if distance < (nearest?.distance ?? .greatestFiniteMagnitude) {
                    nearest = (country, ring, distance)
                }
            }
            if home != nil { break }
        }
        if home == nil, let nearest, nearest.distance < 9 {      // within ~3°
            // Nearest ring, but biased towards the mainland: Sydney sits
            // just outside a 1:50m Australia, and the closest scrap of
            // coastline to a harbour city is often a harbour island. Any
            // ring within half a degree of the winner is fair game, and
            // the biggest of those is the one worth drawing.
            let slack = (nearest.distance.squareRoot() + 0.5)
            let ring = nearest.country.rings
                .filter { squaredDistance(from: point, toVerticesOf: $0) <= slack * slack }
                .max { area(of: bounds(of: $0)) < area(of: bounds(of: $1)) }
            home = (nearest.country, ring ?? nearest.ring)
        }
        guard let home else { return nil }

        // Keep the rings that belong to this landmass: the home ring, plus
        // any island close enough to it to be worth the paper. The reach is
        // a fraction of the landmass rather than a fixed distance, and a
        // tight one — Shetland is only 150 km off Scotland, but letting it
        // in stretches a chart of Britain by a fifth for one small island.
        var box = bounds(of: home.ring)
        let padX = max(0.3, (box.maxX - box.minX) * 0.12)
        let padY = max(0.3, (box.maxY - box.minY) * 0.12)
        let reach = CGRect(x: box.minX - padX, y: box.minY - padY,
                           width: (box.maxX - box.minX) + padX * 2,
                           height: (box.maxY - box.minY) + padY * 2)
        var rings: [[CGPoint]] = []
        for ring in home.country.rings where bounds(of: ring).intersects(reach) {
            rings.append(ring)
            box = box.union(bounds(of: ring))
        }
        if rings.isEmpty { rings = [home.ring] }

        let cities = (atlas.cities[home.country.code] ?? []).filter {
            box.contains(CGPoint(x: $0.longitude, y: $0.latitude))
        }
        return Region(code: home.country.code,
                      name: home.country.name,
                      rings: rings,
                      cities: cities,
                      minLongitude: box.minX, maxLongitude: box.maxX,
                      minLatitude: box.minY, maxLatitude: box.maxY)
    }

    // ── Geometry ───────────────────────────────────────────────────────

    /// Ray casting, in plain degrees. Good enough at this scale: the rings
    /// are already rounded to about a kilometre.
    fileprivate static func contains(_ ring: [CGPoint], _ point: CGPoint) -> Bool {
        guard ring.count > 2 else { return false }
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let a = ring[i], b = ring[j]
            if (a.y > point.y) != (b.y > point.y) {
                let t = (point.y - a.y) / (b.y - a.y)
                if point.x < a.x + t * (b.x - a.x) { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    private static func squaredDistance(from point: CGPoint, toVerticesOf ring: [CGPoint]) -> Double {
        var best = Double.greatestFiniteMagnitude
        for vertex in ring {
            let dx = vertex.x - point.x, dy = vertex.y - point.y
            best = min(best, Double(dx * dx + dy * dy))
        }
        return best
    }

    private static func area(of box: CGRect) -> Double {
        Double(box.width * box.height)
    }

    private static func bounds(of ring: [CGPoint]) -> CGRect {
        var minX = Double.greatestFiniteMagnitude, minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude, maxY = -Double.greatestFiniteMagnitude
        for point in ring {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // ── The bundled file ───────────────────────────────────────────────

    private struct Country {
        var code: String
        var name: String
        var rings: [[CGPoint]]
    }

    private struct Atlas {
        var countries: [String: Country]
        var cities: [String: [Place]]
    }

    /// Parsed once, on whichever thread asks first (`static let` is
    /// lazy and thread-safe); callers keep it off the main actor.
    private static let atlas: Atlas? = loadAtlas()

    private static func loadAtlas() -> Atlas? {
        guard let url = Bundle.main.url(forResource: "Atlas", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var countries: [String: Country] = [:]
        if let raw = root["countries"] as? [String: [String: Any]] {
            for (code, entry) in raw {
                guard let flat = entry["rings"] as? [[Int]] else { continue }
                // Stored as hundredths of a degree, longitude then latitude.
                let rings = flat.map { ring -> [CGPoint] in
                    stride(from: 0, to: ring.count - 1, by: 2).map {
                        CGPoint(x: Double(ring[$0]) / 100, y: Double(ring[$0 + 1]) / 100)
                    }
                }
                countries[code] = Country(code: code,
                                          name: entry["name"] as? String ?? code,
                                          rings: rings)
            }
        }

        var cities: [String: [Place]] = [:]
        if let raw = root["cities"] as? [String: [[String: Any]]] {
            for (code, entries) in raw {
                cities[code] = entries.compactMap { entry in
                    guard let name = entry["n"] as? String,
                          let latitude = entry["y"] as? Double,
                          let longitude = entry["x"] as? Double else { return nil }
                    return Place(name: name, latitude: latitude, longitude: longitude,
                                 population: entry["p"] as? Int ?? 0,
                                 isCapital: (entry["c"] as? Int ?? 0) == 1)
                }
            }
        }
        return Atlas(countries: countries, cities: cities)
    }
}

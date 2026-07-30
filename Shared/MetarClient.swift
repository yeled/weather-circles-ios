import Foundation

/// Nearest-airport METAR via aviationweather.gov — the observational
/// source for two things a forecast model can't be trusted for: cloud
/// *genus* (CB / TCU suffixes on cloud-layer groups; the API's decoded
/// `clouds` array silently drops those, so `rawOb` is parsed directly)
/// and W₁, the past few hours' most significant weather. Both exist
/// because global models routinely miss small-scale convection outright
/// — a real storm can simply never appear in Open-Meteo's hourly
/// `weather_code` trace, no matter how far back you look.
enum MetarClient {
    struct Report: Decodable {
        let icaoId: String
        let lat: Double?
        let lon: Double?
        let obsTime: Int?
        let rawOb: String
    }

    struct Findings {
        var genus: (genus: StationObservation.LowCloudGenus, station: String)?
        var pastWeather: (key: StationObservation.PrecipKey, station: String)?
    }

    /// One fetch — `hours=6` so past weather has a real window to scan —
    /// serving both lookups, so a widget or app refresh spends a single
    /// request on aviationweather.gov rather than two.
    static func findings(latitude: Double, longitude: Double) async -> Findings {
        var components = URLComponents(string: "https://aviationweather.gov/api/data/metar")!
        components.queryItems = [
            .init(name: "bbox", value: String(format: "%.3f,%.3f,%.3f,%.3f",
                                              max(-89, latitude - 1), longitude - 1,
                                              min(89, latitude + 1), longitude + 1)),
            .init(name: "format", value: "json"),
            .init(name: "hours", value: "6"),
        ]
        guard let url = components.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let reports = try? JSONDecoder().decode([Report].self, from: data) else {
            return Findings()
        }

        // Flat-earth squared degrees is fine for ranking stations in a ±1° box.
        func closeness(_ report: Report) -> Double {
            guard let lat = report.lat, let lon = report.lon else {
                return .greatestFiniteMagnitude
            }
            let dLat = lat - latitude
            let dLon = (lon - longitude) * cos(latitude * .pi / 180)
            return dLat * dLat + dLon * dLon
        }
        let now = Date().timeIntervalSince1970
        func isFresh(_ report: Report) -> Bool {
            guard let observed = report.obsTime else { return false }
            return now - Double(observed) <= 2 * 3600
        }

        var findings = Findings()

        // Genus: nearest report that's both fresh and actually describes
        // the sky. Nil means the nearest station sees no CB/TCU right
        // now — which is itself the observation, so we don't hunt further
        // afield for a more dramatic answer.
        let skyUsable = reports.filter { isFresh($0) && skyTokens(in: $0.rawOb) != nil }
        if let nearestSky = skyUsable.min(by: { closeness($0) < closeness($1) }),
           let genus = genus(fromRawOb: nearestSky.rawOb) {
            findings.genus = (genus, nearestSky.icaoId)
        }

        // Past weather: the nearest *currently reporting* station, then
        // everything that station said across the whole window — not
        // just its latest report, since the storm may have passed.
        if let nearestStation = reports.filter(isFresh).min(by: { closeness($0) < closeness($1) })?.icaoId {
            let severest = reports
                .filter { $0.icaoId == nearestStation }
                .compactMap { presentWeather(fromRawOb: $0.rawOb) }
                .max { StationObservation.severity(of: $0) < StationObservation.severity(of: $1) }
            if let severest {
                findings.pastWeather = (severest, nearestStation)
            }
        }

        return findings
    }

    /// Cloud-layer / sky tokens from the report body. Everything after
    /// " RMK" is ignored, so remarks like "CB DSNT W" (a cumulonimbus
    /// somewhere over the horizon) never count as the station's own sky.
    private static func skyTokens(in rawOb: String) -> [Substring]? {
        let body = rawOb.components(separatedBy: " RMK").first ?? rawOb
        let tokens = body.split(separator: " ").filter { token in
            token.hasPrefix("FEW") || token.hasPrefix("SCT")
                || token.hasPrefix("BKN") || token.hasPrefix("OVC")
                || token == "CAVOK" || token == "NCD" || token == "NSC"
                || token == "CLR" || token == "SKC"
        }
        return tokens.isEmpty ? nil : tokens
    }

    /// Layer-attached genus only: FEW026CB, SCT020TCU, … CB outranks TCU.
    static func genus(fromRawOb rawOb: String) -> StationObservation.LowCloudGenus? {
        guard let tokens = skyTokens(in: rawOb) else { return nil }
        var genus: StationObservation.LowCloudGenus?
        for token in tokens {
            if token.hasSuffix("CB") { return .cumulonimbus }
            if token.hasSuffix("TCU") { genus = .toweringCumulus }
        }
        return genus
    }

    /// The most severe present-weather group in a METAR body, translated
    /// to the app's precip alphabet. Trend groups (`TEMPO`/`BECMG`) and
    /// their tail are dropped first — those are outlooks, not what the
    /// station is reporting for itself right now — and `VC` ("in the
    /// vicinity", i.e. seen but not overhead) tokens don't count either.
    static func presentWeather(fromRawOb rawOb: String) -> StationObservation.PrecipKey? {
        var body = rawOb.components(separatedBy: " RMK").first ?? rawOb
        for trend in [" TEMPO", " BECMG"] {
            if let range = body.range(of: trend) {
                body = String(body[body.startIndex..<range.lowerBound])
            }
        }

        var best: StationObservation.PrecipKey?
        func consider(_ key: StationObservation.PrecipKey) {
            if best == nil || StationObservation.severity(of: key) > StationObservation.severity(of: best!) {
                best = key
            }
        }
        for token in body.split(separator: " ") where !token.hasPrefix("VC") {
            let t = String(token)
            if t.contains("TS") { consider(.thunder) }
            else if t.contains("GR") || t.contains("FZRA") || t.contains("FZDZ") || t.contains("PL") {
                consider(.sleet)
            } else if t.contains("SH"), t.contains("SN") { consider(.snowShower) }
            else if t.contains("SN") { consider(.snow) }
            else if t.contains("+RA") || t.contains("SHRA") { consider(.heavyRain) }
            else if t.contains("RA") { consider(.rain) }
            else if t.contains("DZ") { consider(.drizzle) }
            else if t.contains("FG") { consider(.fog) }
            else if t.contains("BR") { consider(.mist) }
        }
        return best
    }
}

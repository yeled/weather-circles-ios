import Foundation

/// Nearest-airport METAR via aviationweather.gov — the one observational
/// source that reports cloud *genus*, and only for convective low cloud:
/// CB / TCU suffixes on cloud-layer groups. The API's decoded `clouds`
/// array silently drops those suffixes, so we parse `rawOb` ourselves.
enum MetarClient {
    struct Report: Decodable {
        let icaoId: String
        let lat: Double?
        let lon: Double?
        let obsTime: Int?
        let rawOb: String
    }

    /// The nearest usable report's convective low-cloud genus. "Usable" =
    /// fresh (≤ 2 h) and actually reporting sky condition. Nil means the
    /// nearest station reports no CB/TCU — which is itself the observation,
    /// so we don't go hunting further afield for a more dramatic answer.
    static func lowCloudGenus(latitude: Double, longitude: Double) async
        -> (genus: StationObservation.LowCloudGenus, station: String)? {
        var components = URLComponents(string: "https://aviationweather.gov/api/data/metar")!
        components.queryItems = [
            .init(name: "bbox", value: String(format: "%.3f,%.3f,%.3f,%.3f",
                                              max(-89, latitude - 1), longitude - 1,
                                              min(89, latitude + 1), longitude + 1)),
            .init(name: "format", value: "json"),
        ]
        guard let url = components.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let reports = try? JSONDecoder().decode([Report].self, from: data) else {
            return nil
        }

        let now = Date().timeIntervalSince1970
        let usable = reports.filter { report in
            if let observed = report.obsTime, now - Double(observed) > 2 * 3600 {
                return false
            }
            return skyTokens(in: report.rawOb) != nil
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

        guard let nearest = usable.min(by: { closeness($0) < closeness($1) }),
              let genus = genus(fromRawOb: nearest.rawOb) else {
            return nil
        }
        return (genus, nearest.icaoId)
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
}

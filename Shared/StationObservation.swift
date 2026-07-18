import Foundation

/// One station-model observation: everything `weather_circle.py` plots —
/// cloud cover (oktas), wind (knots, direction *from*), present weather,
/// temperature — plus today's forecast high/low, carried alongside the
/// observation but never encoded into the circle itself.
struct StationObservation: Codable, Equatable {
    var fetchedAt: Date
    var latitude: Double
    var longitude: Double
    var placeName: String?

    var temperatureC: Double
    var weatherCode: Int
    var cloudCoverPercent: Double
    var windSpeedKnots: Double
    var windFromDegrees: Double

    var todayHighC: Double?
    var todayLowC: Double?

    /// Cloud cover in eighths, as the Python does it: `round(cloud / 12.5)`.
    var oktas: Int {
        min(8, max(0, Int((cloudCoverPercent / 12.5).rounded())))
    }

    /// WMO code 48 — sky obscured, drawn as an X instead of an okta fill.
    var skyObscured: Bool { weatherCode == 48 }

    enum PrecipKey: String, Codable {
        case drizzle, rain, heavyRain, sleet, snow, snowShower, thunder, mist, fog
    }

    /// WMO weather-code → UK station-model glyph (Python `precip_for`).
    var precip: PrecipKey? {
        switch weatherCode {
        case 51, 53, 55:     .drizzle
        case 56, 57, 66, 67: .sleet
        case 61, 63, 80, 81: .rain
        case 65, 82:         .heavyRain
        case 71, 73, 75, 77: .snow
        case 85, 86:         .snowShower
        case 95, 96, 99:     .thunder
        case 45:             .mist
        case 48:             .fog
        default:             nil
        }
    }

    var roundedTemp: Int { Int(temperatureC.rounded()) }

    var compassPoint: String {
        let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                      "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((windFromDegrees / 22.5).rounded()) % 16
        return points[(index + 16) % 16]
    }

    var windText: String {
        windSpeedKnots < 1 ? "Calm" : "\(compassPoint) \(Int(windSpeedKnots.rounded())) kn"
    }

    var highLowText: String? {
        guard let high = todayHighC, let low = todayLowC else { return nil }
        return "H \(Int(high.rounded()))°  L \(Int(low.rounded()))°"
    }

    var accessibilitySummary: String {
        var parts = ["\(roundedTemp) degrees", windText, "\(oktas) of 8 cloud"]
        if let precip { parts.append(precip.rawValue) }
        if let highLowText { parts.append(highLowText) }
        return parts.joined(separator: ", ")
    }

    /// Placeholder for previews and widget galleries: London, the original
    /// script's default location, on a blustery rainy day.
    static let sample = StationObservation(
        fetchedAt: Date(),
        latitude: 51.5074, longitude: -0.1278, placeName: "London",
        temperatureC: 14, weatherCode: 61,
        cloudCoverPercent: 75, windSpeedKnots: 18, windFromDegrees: 230,
        todayHighC: 17, todayLowC: 9)
}

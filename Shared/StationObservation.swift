import Foundation

/// One station-model observation: everything `weather_circle.py` plots —
/// cloud cover (oktas), wind (knots, direction *from*), present weather,
/// temperature — plus the rest of the Met Office station-model slots
/// (dew point, MSLP, 3-hour pressure tendency, past weather, visibility)
/// and today's forecast high/low, carried alongside the observation but
/// never encoded into the circle itself.
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

    // Met Office station-model extras (all optional so older cached
    // observations still decode).
    var dewPointC: Double?
    var pressureMSLhPa: Double?
    var pressureChange3hPa: Double?
    var pressureTendency: PressureTendency?
    /// Fallback W₁ source: the forecast model's own hourly `weather_code`
    /// diagnostic over `past_hours`. Kept for locations with no nearby
    /// METAR station, but it's a model guess, not an observation — global
    /// models routinely miss small-scale convection entirely, so
    /// `pastWeatherMETAR` (real ground truth) wins whenever it's present.
    var pastSignificantWeatherCode: Int?
    var visibilityMeters: Double?
    /// ECMWF native ptype (GRIB 4.201: 1 rain, 3 freezing rain, 4/7 mixed,
    /// 5 snow, 6 wet snow, 8 ice pellets, 12 freezing drizzle).
    var precipitationTypeCode: Int?
    var precipitationMM: Double?

    /// C_L from the nearest METAR — the only genus any observation source
    /// machine-reports, and only for convective low cloud. C_M/C_H aren't
    /// available from anything, so they're never faked.
    var lowCloudGenus: LowCloudGenus?
    var genusStationICAO: String?

    /// W₁ from the nearest METAR's present-weather groups over the last
    /// few hours — real ground truth, same rationale as `lowCloudGenus`:
    /// a global forecast model's hourly diagnostic can miss a real,
    /// localized storm outright.
    var pastWeatherMETAR: PrecipKey?
    var pastWeatherStationICAO: String?

    enum LowCloudGenus: String, Codable {
        case toweringCumulus   // WMO C_L = 2
        case cumulonimbus      // WMO C_L = 9
    }

    /// TRMNL-style rolling forecast: eight 2-hour slots from the current
    /// hour, each carrying its window's most significant hour.
    var forecastSlots: [ForecastSlot]?

    struct ForecastSlot: Codable, Equatable {
        var localHour: Int      // slot start, in the location's own timezone
        var temperatureC: Double
        var weatherCode: Int
        var cloudCoverPercent: Double
        var windSpeedKnots: Double
        var windFromDegrees: Double

        var hourLabel: String { String(format: "%02d", localHour) }

        /// A minimal observation so StationPlot can draw the mini circle.
        func asObservation() -> StationObservation {
            StationObservation(
                fetchedAt: .distantPast, latitude: 0, longitude: 0,
                temperatureC: temperatureC, weatherCode: weatherCode,
                cloudCoverPercent: cloudCoverPercent,
                windSpeedKnots: windSpeedKnots,
                windFromDegrees: windFromDegrees)
        }
    }

    /// Seven-day outlook. Aggregation philosophy: discrete weather takes
    /// the day's *most severe* code (Open-Meteo's daily semantics — the
    /// same instinct as the TRMNL slot rule), cloud cover takes the
    /// *mean* (an okta is an areal average by nature), wind takes the
    /// day's *max* speed with the dominant direction — a mean barb would
    /// lie about gusty days. Never a flat average of everything: that
    /// washes morning-fog-then-thunderstorm into meaningless drizzle.
    var dailyForecast: [DailyForecast]?

    struct DailyForecast: Codable, Equatable {
        var dateISO: String      // "2026-07-19", location-local
        var highC: Double
        var lowC: Double
        var weatherCode: Int
        var cloudCoverMeanPercent: Double
        var windMaxKnots: Double
        var windDominantDegrees: Double
        var precipitationSumMM: Double

        /// A minimal observation so StationPlot can draw the day circle.
        func asObservation() -> StationObservation {
            StationObservation(
                fetchedAt: .distantPast, latitude: 0, longitude: 0,
                temperatureC: highC, weatherCode: weatherCode,
                cloudCoverPercent: cloudCoverMeanPercent,
                windSpeedKnots: windMaxKnots,
                windFromDegrees: windDominantDegrees)
        }

        var windText: String {
            windMaxKnots < 1 ? "Calm"
                : "\(StationObservation.compassPoint(for: windDominantDegrees)) \(Int(windMaxKnots.rounded()))"
        }
    }

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
    static func precipKey(forWMOCode code: Int) -> PrecipKey? {
        switch code {
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

    var precip: PrecipKey? { Self.precipKey(forWMOCode: weatherCode) }

    /// The ww glyph to draw: the WMO-code key, phase-corrected by ECMWF's
    /// native precipitation type when precip is actually falling. The code
    /// knows *character* (drizzle, shower, thunder); ptype knows *phase*
    /// (freezing rain, wet snow, mixed) that the derived code often misses.
    var effectivePrecip: PrecipKey? {
        let base = precip
        guard let ptype = precipitationTypeCode, (precipitationMM ?? 0) > 0.05 else {
            return base
        }
        if base == .thunder { return base }
        switch ptype {
        case 1:         return base ?? .rain      // rain: keep drizzle/shower character
        case 3, 8, 12:  return .sleet             // freezing rain / ice pellets / freezing drizzle
        case 4, 7:      return .sleet             // mixed rain and snow
        case 5, 6:      return .snow              // snow / wet snow
        default:        return base
        }
    }

    /// W₁ — most significant past weather. Real METAR observation first;
    /// the model's hourly-code guess only stands in where no station is
    /// near enough to have one.
    var pastWeather: PrecipKey? {
        pastWeatherMETAR ?? pastSignificantWeatherCode.flatMap(Self.precipKey(forWMOCode:))
    }

    /// Severity ranking from the TRMNL plugin's README: thunder > heavy
    /// rain > snow shower > snow > sleet > rain > drizzle > fog > mist.
    static func severity(of key: PrecipKey) -> Int {
        switch key {
        case .thunder:    9
        case .heavyRain:  8
        case .snowShower: 7
        case .snow:       6
        case .sleet:      5
        case .rain:       4
        case .drizzle:    3
        case .fog:        2
        case .mist:       1
        }
    }

    /// WMO "a" — the shape of the 3-hour barograph trace.
    enum PressureTendency: String, Codable {
        case rising, falling, steady
        case riseThenFall, fallThenRise
        case steadyThenRise, steadyThenFall

        /// Classify from the values 3 h ago, 1 h ago, and now.
        static func from(p3: Double, p1: Double, now: Double) -> (PressureTendency, Double) {
            let net = now - p3
            let early = p1 - p3
            let late = now - p1
            let tendency: PressureTendency
            if abs(net) < 0.1 {
                tendency = .steady
            } else if net > 0 {
                if late < -0.1 { tendency = .riseThenFall }        // a=0
                else if early < -0.1 { tendency = .steadyThenRise } // a=3
                else { tendency = .rising }                         // a=2
            } else {
                if late > 0.1 { tendency = .fallThenRise }          // a=5
                else if early > 0.1 { tendency = .steadyThenFall }  // a=8
                else { tendency = .falling }                        // a=7
            }
            return (tendency, net)
        }
    }

    // ── Formatting for the plot's annotation slots ─────────────────────

    var roundedTemp: Int { Int(temperatureC.rounded()) }
    var dewPointRounded: Int? { dewPointC.map { Int($0.rounded()) } }

    /// PPP — MSLP in coded synoptic form: tenths of hPa, last three digits
    /// (1021.6 → "216", 998.7 → "987").
    var pressureCodedPPP: String? {
        guard let pressure = pressureMSLhPa else { return nil }
        let tenths = ((Int((pressure * 10).rounded()) % 1000) + 1000) % 1000
        return String(format: "%03d", tenths)
    }

    /// pp — signed 3-hour change in tenths of hPa ("+11" = +1.1 hPa).
    var pressureChangeCodedPP: String? {
        guard let change = pressureChange3hPa else { return nil }
        return String(format: "%+d", Int((change * 10).rounded()))
    }

    var visibilityText: String? {
        guard let v = visibilityMeters else { return nil }
        if v < 1000 { return "\(Int((v / 100).rounded()) * 100) m" }
        return "\(Int((v / 1000).rounded())) km"
    }

    static func compassPoint(for degrees: Double) -> String {
        let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                      "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((degrees / 22.5).rounded()) % 16
        return points[(index + 16) % 16]
    }

    var compassPoint: String { Self.compassPoint(for: windFromDegrees) }

    var windText: String {
        windSpeedKnots < 1 ? "Calm" : "\(compassPoint) \(Int(windSpeedKnots.rounded())) kn"
    }

    var highLowText: String? {
        guard let high = todayHighC, let low = todayLowC else { return nil }
        return "H \(Int(high.rounded()))°  L \(Int(low.rounded()))°"
    }

    var genusText: String? {
        guard let lowCloudGenus else { return nil }
        let label = lowCloudGenus == .cumulonimbus ? "CB" : "TCU"
        return genusStationICAO.map { "\(label) at \($0)" } ?? label
    }

    var accessibilitySummary: String {
        var parts = ["\(roundedTemp) degrees", windText, "\(oktas) of 8 cloud"]
        if let effectivePrecip { parts.append(effectivePrecip.rawValue) }
        if let dew = dewPointRounded { parts.append("dew point \(dew)") }
        if let pressure = pressureMSLhPa {
            parts.append("\(Int(pressure.rounded())) hectopascals")
        }
        if let lowCloudGenus {
            parts.append(lowCloudGenus == .cumulonimbus
                         ? "cumulonimbus observed" : "towering cumulus observed")
        }
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
        todayHighC: 17, todayLowC: 9,
        dewPointC: 11, pressureMSLhPa: 1004.8,
        pressureChange3hPa: -1.2, pressureTendency: .falling,
        pastSignificantWeatherCode: 61, visibilityMeters: 8000,
        precipitationTypeCode: nil, precipitationMM: 0.4)
}

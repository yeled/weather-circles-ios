import Foundation

/// Open-Meteo client. The `current` block extends the exact query
/// `weather_circle.py` makes (including `wind_speed_unit=kn` — barbs are
/// drawn in knots) with the remaining Met Office station-model slots:
/// dew point, MSLP, precipitation + native ECMWF ptype, visibility. The
/// `hourly` block with `past_hours=6` feeds the 3-hour pressure tendency
/// and the past-weather (W₁) glyph; `daily` adds today's high/low.
enum OpenMeteoClient {
    enum FetchError: Error {
        case badURL
        case badResponse
    }

    struct Response: Decodable {
        struct Current: Decodable {
            let time: String
            let temperature2m: Double
            let weatherCode: Int
            let cloudCover: Double?
            let windSpeed10m: Double?
            let windDirection10m: Double?
            let dewPoint2m: Double?
            let pressureMsl: Double?
            let precipitation: Double?
            let precipitationType: Double?
            let visibility: Double?

            enum CodingKeys: String, CodingKey {
                case time
                case temperature2m = "temperature_2m"
                case weatherCode = "weather_code"
                case cloudCover = "cloud_cover"
                case windSpeed10m = "wind_speed_10m"
                case windDirection10m = "wind_direction_10m"
                case dewPoint2m = "dew_point_2m"
                case pressureMsl = "pressure_msl"
                case precipitation
                case precipitationType = "precipitation_type"
                case visibility
            }
        }

        struct Hourly: Decodable {
            let time: [String]
            let pressureMsl: [Double?]?
            let weatherCode: [Int?]?
            let temperature2m: [Double?]?
            let cloudCover: [Double?]?
            let windSpeed10m: [Double?]?
            let windDirection10m: [Double?]?

            enum CodingKeys: String, CodingKey {
                case time
                case pressureMsl = "pressure_msl"
                case weatherCode = "weather_code"
                case temperature2m = "temperature_2m"
                case cloudCover = "cloud_cover"
                case windSpeed10m = "wind_speed_10m"
                case windDirection10m = "wind_direction_10m"
            }
        }

        struct Daily: Decodable {
            let temperature2mMax: [Double]
            let temperature2mMin: [Double]

            enum CodingKeys: String, CodingKey {
                case temperature2mMax = "temperature_2m_max"
                case temperature2mMin = "temperature_2m_min"
            }
        }

        let current: Current
        let hourly: Hourly?
        let daily: Daily?
    }

    static func observation(latitude: Double, longitude: Double,
                            placeName: String? = nil) async throws -> StationObservation {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(format: "%.4f", latitude)),
            .init(name: "longitude", value: String(format: "%.4f", longitude)),
            .init(name: "current", value: "weather_code,temperature_2m,cloud_cover,wind_speed_10m,wind_direction_10m,dew_point_2m,pressure_msl,precipitation,precipitation_type,visibility"),
            .init(name: "hourly", value: "pressure_msl,weather_code,temperature_2m,cloud_cover,wind_speed_10m,wind_direction_10m"),
            .init(name: "past_hours", value: "6"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "forecast_days", value: "2"),
            .init(name: "wind_speed_unit", value: "kn"),
            .init(name: "timezone", value: "auto"),
        ]
        guard let url = components.url else { throw FetchError.badURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw FetchError.badResponse
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)

        // 3-hour pressure tendency and past weather, from the hourly trace.
        // hourly.time[i] are hour marks; the current hour is the one whose
        // "yyyy-MM-ddTHH" prefix matches current.time.
        var tendency: StationObservation.PressureTendency?
        var change3h: Double?
        var pastCode: Int?
        var slots: [StationObservation.ForecastSlot]?
        if let hourly = decoded.hourly {
            let hourPrefix = String(decoded.current.time.prefix(13))
            if let idx = hourly.time.firstIndex(where: { $0.hasPrefix(hourPrefix) }) {
                if let trace = hourly.pressureMsl, idx >= 3, idx < trace.count,
                   let now = decoded.current.pressureMsl,
                   let p3 = trace[idx - 3], let p1 = trace[idx - 1] {
                    (tendency, change3h) = {
                        let (t, net) = StationObservation.PressureTendency
                            .from(p3: p3, p1: p1, now: now)
                        return (t, net)
                    }()
                }
                if let codes = hourly.weatherCode, idx <= codes.count {
                    pastCode = codes[max(0, idx - 6)..<idx]
                        .compactMap { $0 }
                        .compactMap { code in
                            StationObservation.precipKey(forWMOCode: code)
                                .map { (code, StationObservation.severity(of: $0)) }
                        }
                        .max { $0.1 < $1.1 }?.0
                }
                // TRMNL rolling slots: 8 × 2 h from the current hour, each
                // showing its window's most significant hour — ranked by
                // precip severity, falling back to the cloudiest (the
                // plugin's rule, so a shower between slots still shows up).
                if let temps = hourly.temperature2m, let clouds = hourly.cloudCover,
                   let winds = hourly.windSpeed10m, let dirs = hourly.windDirection10m,
                   let codes = hourly.weatherCode {
                    func significance(_ i: Int) -> Double {
                        let code = codes.indices.contains(i) ? (codes[i] ?? 0) : 0
                        let cloud = clouds.indices.contains(i) ? (clouds[i] ?? 0) : 0
                        let severity = StationObservation.precipKey(forWMOCode: code)
                            .map(StationObservation.severity(of:)) ?? 0
                        return Double(severity) * 1000 + cloud
                    }
                    var built: [StationObservation.ForecastSlot] = []
                    for slot in 0..<8 {
                        let start = idx + slot * 2
                        let window = [start, start + 1].filter { temps.indices.contains($0) }
                        guard hourly.time.indices.contains(start),
                              let hour = Int(hourly.time[start].dropFirst(11).prefix(2)),
                              let pick = window.max(by: { significance($0) < significance($1) }),
                              let temp = temps[pick] else { continue }
                        built.append(StationObservation.ForecastSlot(
                            localHour: hour,
                            temperatureC: temp,
                            weatherCode: (codes.indices.contains(pick) ? codes[pick] : nil) ?? 0,
                            cloudCoverPercent: (clouds.indices.contains(pick) ? clouds[pick] : nil) ?? 0,
                            windSpeedKnots: (winds.indices.contains(pick) ? winds[pick] : nil) ?? 0,
                            windFromDegrees: (dirs.indices.contains(pick) ? dirs[pick] : nil) ?? 0))
                    }
                    if !built.isEmpty { slots = built }
                }
            }
        }

        return StationObservation(
            fetchedAt: Date(),
            latitude: latitude,
            longitude: longitude,
            placeName: placeName,
            temperatureC: decoded.current.temperature2m,
            weatherCode: decoded.current.weatherCode,
            cloudCoverPercent: decoded.current.cloudCover ?? 0,
            windSpeedKnots: decoded.current.windSpeed10m ?? 0,
            windFromDegrees: decoded.current.windDirection10m ?? 0,
            todayHighC: decoded.daily?.temperature2mMax.first,
            todayLowC: decoded.daily?.temperature2mMin.first,
            dewPointC: decoded.current.dewPoint2m,
            pressureMSLhPa: decoded.current.pressureMsl,
            pressureChange3hPa: change3h,
            pressureTendency: tendency,
            pastSignificantWeatherCode: pastCode,
            visibilityMeters: decoded.current.visibility,
            precipitationTypeCode: decoded.current.precipitationType.map { Int($0) },
            precipitationMM: decoded.current.precipitation,
            forecastSlots: slots)
    }
}

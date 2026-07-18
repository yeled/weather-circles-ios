import Foundation

/// Minimal Open-Meteo client. The `current` block is the exact query
/// `weather_circle.py` makes (including `wind_speed_unit=kn` — barbs are
/// drawn in knots); the `daily` block adds today's high/low.
enum OpenMeteoClient {
    enum FetchError: Error {
        case badURL
        case badResponse
    }

    struct Response: Decodable {
        struct Current: Decodable {
            let temperature2m: Double
            let weatherCode: Int
            let cloudCover: Double?
            let windSpeed10m: Double?
            let windDirection10m: Double?

            enum CodingKeys: String, CodingKey {
                case temperature2m = "temperature_2m"
                case weatherCode = "weather_code"
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
        let daily: Daily?
    }

    static func observation(latitude: Double, longitude: Double,
                            placeName: String? = nil) async throws -> StationObservation {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(format: "%.4f", latitude)),
            .init(name: "longitude", value: String(format: "%.4f", longitude)),
            .init(name: "current", value: "weather_code,temperature_2m,cloud_cover,wind_speed_10m,wind_direction_10m"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "forecast_days", value: "1"),
            .init(name: "wind_speed_unit", value: "kn"),
            .init(name: "timezone", value: "auto"),
        ]
        guard let url = components.url else { throw FetchError.badURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw FetchError.badResponse
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)

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
            todayLowC: decoded.daily?.temperature2mMin.first)
    }
}

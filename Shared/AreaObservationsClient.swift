import Foundation

/// Current conditions for a handful of scattered points in one request.
///
/// Open-Meteo takes comma-separated coordinates and answers with one array
/// element per point, so a whole chart of a dozen cities costs a single
/// call. Only the fields the plain repo circle draws are asked for (cloud,
/// wind, weather code, temperature): no hourly, no daily, and deliberately
/// no METAR leg — a dozen station lookups to decorate thumbnails would be
/// rude to aviationweather.gov and slow to boot.
enum AreaObservationsClient {
    enum FetchError: Error {
        case badURL
        case badResponse
    }

    struct Point: Equatable {
        var name: String
        var latitude: Double
        var longitude: Double
    }

    struct Reading: Identifiable, Equatable {
        var id: Int                 // index into the requested points
        var name: String
        var latitude: Double
        var longitude: Double
        var observation: StationObservation
    }

    static func fetch(points: [Point]) async throws -> [Reading] {
        guard !points.isEmpty else { return [] }

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: points.map { String(format: "%.4f", $0.latitude) }
                                                 .joined(separator: ",")),
            .init(name: "longitude", value: points.map { String(format: "%.4f", $0.longitude) }
                                                  .joined(separator: ",")),
            .init(name: "current", value: "weather_code,temperature_2m,cloud_cover,wind_speed_10m,wind_direction_10m"),
            .init(name: "wind_speed_unit", value: "kn"),
        ]
        guard let url = components.url else { throw FetchError.badURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw FetchError.badResponse
        }
        // A single coordinate comes back as an object, a list as an array.
        let elements: [Element]
        if let many = try? JSONDecoder().decode([Element].self, from: data) {
            elements = many
        } else {
            elements = [try JSONDecoder().decode(Element.self, from: data)]
        }

        let now = Date()
        var readings: [Reading] = []
        for (index, point) in points.enumerated() {
            guard elements.indices.contains(index) else { break }
            let current = elements[index].current
            // Plotted where we asked, not at the model cell centre the API
            // echoes back: the circle belongs to the city, not to the grid.
            readings.append(Reading(
                id: index,
                name: point.name,
                latitude: point.latitude,
                longitude: point.longitude,
                observation: StationObservation(
                    fetchedAt: now,
                    latitude: point.latitude,
                    longitude: point.longitude,
                    placeName: point.name,
                    temperatureC: current.temperature2m ?? 0,
                    weatherCode: current.weatherCode ?? 0,
                    cloudCoverPercent: current.cloudCover ?? 0,
                    windSpeedKnots: current.windSpeed10m ?? 0,
                    windFromDegrees: current.windDirection10m ?? 0)))
        }
        guard !readings.isEmpty else { throw FetchError.badResponse }
        return readings
    }

    /// One element of the multi-location response.
    private struct Element: Decodable {
        struct Current: Decodable {
            let temperature2m: Double?
            let weatherCode: Int?
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

        let latitude: Double
        let longitude: Double
        let current: Current
    }
}

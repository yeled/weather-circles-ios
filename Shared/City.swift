import Foundation

/// A pinned place from the Open-Meteo geocoder.
struct City: Codable, Equatable, Hashable, Identifiable {
    var id: Int
    var name: String
    var admin1: String?
    var country: String?
    var latitude: Double
    var longitude: Double

    var subtitle: String {
        [admin1, country].compactMap { $0 }.joined(separator: ", ")
    }
}

/// Selected city + recents, in the App Group so the widget follows along.
enum CityStore {
    private static let selectedKey = "selectedCity"
    private static let recentsKey = "recentCities"
    private static let recentsCap = 8

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: WeatherStore.appGroupID) ?? .standard
    }

    /// nil = follow the phone's location.
    static var selected: City? {
        get {
            guard let data = defaults.data(forKey: selectedKey) else { return nil }
            return try? JSONDecoder().decode(City.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: selectedKey)
            } else {
                defaults.removeObject(forKey: selectedKey)
            }
        }
    }

    /// Most recent first, deduplicated, capped.
    static var recents: [City] {
        get {
            guard let data = defaults.data(forKey: recentsKey) else { return [] }
            return (try? JSONDecoder().decode([City].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(Array(newValue.prefix(recentsCap))) {
                defaults.set(data, forKey: recentsKey)
            }
        }
    }

    static func noteVisited(_ city: City) {
        recents = [city] + recents.filter { $0.id != city.id }
    }
}

/// Open-Meteo's geocoder — same provider as the weather, no key.
enum GeocodingClient {
    struct Response: Decodable {
        struct Result: Decodable {
            let id: Int
            let name: String
            let latitude: Double
            let longitude: Double
            let country: String?
            let admin1: String?
        }
        let results: [Result]?
    }

    static func search(_ query: String) async throws -> [City] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            .init(name: "name", value: trimmed),
            .init(name: "count", value: "8"),
            .init(name: "language", value: "en"),
            .init(name: "format", value: "json"),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.results ?? []).map {
            City(id: $0.id, name: $0.name, admin1: $0.admin1, country: $0.country,
                 latitude: $0.latitude, longitude: $0.longitude)
        }
    }
}

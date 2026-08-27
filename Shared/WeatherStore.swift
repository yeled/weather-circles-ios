import Foundation

/// Cache shared between the app and the widget via the App Group container.
/// If the group isn't provisioned yet (fresh checkout, no team selected),
/// `UserDefaults(suiteName:)` quietly degrades — the app still works and the
/// widget falls back to fetching with its own location.
enum WeatherStore {
    /// Must match the group in both .entitlements files (Config/).
    static let appGroupID = "group.com.evilforbeginners.weathercircles"

    private static let observationKey = "lastObservation"
    private static let coordinateKey = "lastCoordinate"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func save(_ observation: StationObservation, cityID: Int? = nil) {
        guard let data = try? JSONEncoder().encode(observation) else { return }
        defaults.set(data, forKey: observationKey)
        if let cityID {
            defaults.set(data, forKey: cityKey(cityID))
        }
    }

    /// The per-city slot alone — a city-pinned widget's fetch mustn't
    /// become the app-wide "last observation".
    static func saveCityObservation(_ observation: StationObservation, cityID: Int) {
        guard let data = try? JSONEncoder().encode(observation) else { return }
        defaults.set(data, forKey: cityKey(cityID))
    }

    static func loadObservation() -> StationObservation? {
        guard let data = defaults.data(forKey: observationKey) else { return nil }
        return try? JSONDecoder().decode(StationObservation.self, from: data)
    }

    /// Last observation fetched for a pinned city — shown instantly when
    /// the city is re-chosen, while the live fetch replaces it.
    static func loadObservation(cityID: Int) -> StationObservation? {
        guard let data = defaults.data(forKey: cityKey(cityID)) else { return nil }
        return try? JSONDecoder().decode(StationObservation.self, from: data)
    }

    private static func cityKey(_ id: Int) -> String { "observation-city-\(id)" }

    static func saveCoordinate(latitude: Double, longitude: Double) {
        defaults.set([latitude, longitude], forKey: coordinateKey)
    }

    static func loadCoordinate() -> (latitude: Double, longitude: Double)? {
        guard let values = defaults.array(forKey: coordinateKey) as? [Double],
              values.count == 2 else { return nil }
        return (values[0], values[1])
    }
}

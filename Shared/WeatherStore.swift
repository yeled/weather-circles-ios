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

    static func save(_ observation: StationObservation) {
        if let data = try? JSONEncoder().encode(observation) {
            defaults.set(data, forKey: observationKey)
        }
    }

    static func loadObservation() -> StationObservation? {
        guard let data = defaults.data(forKey: observationKey) else { return nil }
        return try? JSONDecoder().decode(StationObservation.self, from: data)
    }

    static func saveCoordinate(latitude: Double, longitude: Double) {
        defaults.set([latitude, longitude], forKey: coordinateKey)
    }

    static func loadCoordinate() -> (latitude: Double, longitude: Double)? {
        guard let values = defaults.array(forKey: coordinateKey) as? [Double],
              values.count == 2 else { return nil }
        return (values[0], values[1])
    }
}

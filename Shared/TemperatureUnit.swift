import Foundation

/// How every temperature the app writes is spelled.
///
/// The station model — and the forecast model behind it — thinks in °C,
/// and that's what a real chart writes in the TT slot. But a reader who
/// thinks in Fahrenheit shouldn't have to convert in their head, so the
/// figure can be written in °F instead.
///
/// Only the *writing* changes, exactly as with `PressureStyle`: the data
/// stays °C throughout, the slots keep their positions, and the guide
/// keeps teaching the same circle.
enum TemperatureUnit: String, Codable, CaseIterable, Identifiable {
    /// The chart's unit — what the app has always shown.
    case celsius
    /// The same air, written for readers who think in °F.
    case fahrenheit

    static let `default` = TemperatureUnit.celsius

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .celsius:    "°C"
        case .fahrenheit: "°F"
        }
    }

    /// Settings-row title.
    var title: String {
        switch self {
        case .celsius:    "Celsius"
        case .fahrenheit: "Fahrenheit"
        }
    }

    /// The same choice shown rather than described, under the title.
    var detail: String {
        switch self {
        case .celsius:    "The chart's own unit: 14 °C stays 14°"
        case .fahrenheit: "The same 14 °C written 57°"
        }
    }

    /// Display rounding from the model's native °C. Rounded after the
    /// conversion, so 14.4 °C is 58 °F (57.9), not 57 (from 14).
    func rounded(_ celsius: Double) -> Int {
        switch self {
        case .celsius:    Int(celsius.rounded())
        case .fahrenheit: Int((celsius * 9 / 5 + 32).rounded())
        }
    }
}

/// The chosen unit, in the App Group beside the pressure style so the
/// widgets write temperatures the same way the app does.
enum TemperatureUnitStore {
    static let key = "temperatureUnit"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: WeatherStore.appGroupID) ?? .standard
    }

    static var current: TemperatureUnit {
        get {
            defaults.string(forKey: key)
                .flatMap(TemperatureUnit.init(rawValue:)) ?? .default
        }
        set { defaults.set(newValue.rawValue, forKey: key) }
    }
}

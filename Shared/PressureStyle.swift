import Foundation

/// How the two pressure slots are written on the plot.
///
/// A surface chart *codes* mean sea-level pressure: tenths of a
/// hectopascal with the leading 9 or 10 dropped, so 1021.6 becomes `216`,
/// and the 3-hour change gets the same treatment (`+11` for +1.1). It's
/// the real notation and the app teaches it — but it's unreadable until
/// you know the rule, so the figure can be printed in full instead.
///
/// Only the *writing* changes. Nothing else about the station model moves:
/// the slots keep their positions, and everything spelled out in the guide
/// and read aloud by VoiceOver was always in full anyway.
enum PressureStyle: String, Codable, CaseIterable, Identifiable {
    /// The chart's own shorthand: `216`, `+11`.
    case coded
    /// The figure itself: `1021.6`, `+1.1`.
    case hectopascals

    /// Chart shorthand — the station model as it's actually drawn, and
    /// what the app has always shown.
    static let `default` = PressureStyle.coded

    var id: String { rawValue }

    /// Settings-row title.
    var title: String {
        switch self {
        case .coded:        "Chart shorthand"
        case .hectopascals: "Hectopascals"
        }
    }

    /// The same choice shown rather than described, under the title.
    var detail: String {
        switch self {
        case .coded:        "1021.6 hPa is written 216, and a 1.1 rise +11"
        case .hectopascals: "The figures in full: 1021.6, and +1.1 for the rise"
        }
    }
}

/// The chosen style, in the App Group beside the pinned city so every
/// target reads the same one. (Today only the app draws the full station
/// model — the widgets show the plain circle, which has no pressure on it
/// — but the setting belongs with the rest of the shared state.)
enum PressureStyleStore {
    static let key = "pressureStyle"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: WeatherStore.appGroupID) ?? .standard
    }

    static var current: PressureStyle {
        get {
            defaults.string(forKey: key)
                .flatMap(PressureStyle.init(rawValue:)) ?? .default
        }
        set { defaults.set(newValue.rawValue, forKey: key) }
    }
}

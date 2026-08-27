import SwiftUI

/// The plain-English half of the station model: what each slot on the
/// circle means, how to read it, a drawn example, and what it happens to
/// say right now. Tapping a piece of the plot opens the matching page;
/// `StationGuideView` lists the lot for the pieces that aren't on today's
/// circle (and for VoiceOver, which can't aim at a Canvas).
extension StationSlot {
    var title: String {
        switch self {
        case .cloud:          "Cloud cover"
        case .wind:           "Wind"
        case .presentWeather: "What's falling now"
        case .temperature:    "Temperature"
        case .dewPoint:       "Dew point"
        case .pressure:       "Pressure"
        case .tendency:       "Pressure trend"
        case .pastWeather:    "What fell earlier"
        case .visibility:     "Visibility"
        case .cloudGenus:     "Cloud type"
        }
    }

    /// The chart abbreviation, so the app teaches the real notation.
    var code: String {
        switch self {
        case .cloud:          "N"
        case .wind:           "dd ff"
        case .presentWeather: "ww"
        case .temperature:    "TT"
        case .dewPoint:       "TdTd"
        case .pressure:       "PPP"
        case .tendency:       "a pp"
        case .pastWeather:    "W₁"
        case .visibility:     "VV"
        case .cloudGenus:     "C\u{2097}"
        }
    }

    func summary(_ pressureStyle: PressureStyle) -> String {
        switch self {
        case .cloud:          "How much of the circle is filled in"
        case .wind:           "The line and feathers sticking out"
        case .presentWeather: "The symbol to the left of the circle"
        case .temperature:    "Upper-left of the circle"
        case .dewPoint:       "Lower-left of the circle"
        case .pressure:       pressureStyle.pressureSummary
        case .tendency:       "To the right, with a little trace"
        case .pastWeather:    "Small symbol, lower-right"
        case .visibility:     "Small figure, upper-left of the symbol"
        case .cloudGenus:     "Below the circle, when it's reported"
        }
    }

    func meaning(_ pressureStyle: PressureStyle,
                 _ temperatureUnit: TemperatureUnit) -> String {
        switch self {
        case .cloud:
            "The circle is the whole sky, seen from above. How much of it is inked in is how much of the sky has cloud in it, measured in eighths — oktas."
        case .wind:
            "The shaft points in the direction the wind is coming from, so a shaft to the south-west means a south-westerly. The feathers on the end count the speed in knots."
        case .presentWeather:
            "The weather happening right now, in the symbol alphabet used on surface charts. No symbol means nothing is falling."
        case .temperature:
            temperatureUnit == .celsius
                ? "Air temperature in °C, in the slot a real chart reserves for it: upper-left of the circle."
                : "Air temperature in °F, in the slot a real chart reserves for it: upper-left of the circle. A real chart writes °C — Settings can put it back."
        case .dewPoint:
            "The temperature the air would have to cool to before its moisture condenses. It's how the chart carries humidity: the closer it is to the air temperature, the damper it feels, and when the two meet you get dew, mist or fog."
        case .pressure:
            pressureStyle.pressureMeaning
        case .tendency:
            pressureStyle.tendencyMeaning
        case .pastWeather:
            "The most significant weather of the past few hours, drawn small and in the same alphabet as the present-weather symbol. A rain symbol here with nothing on the left means it rained earlier and has stopped. Read from the nearest airport's own reports when one's close enough, since a forecast model can miss a storm too local for it to see."
        case .visibility:
            "How far you can see. Real charts code this as a two-figure number; this one just prints the distance."
        case .cloudGenus:
            "The shape of the cloud, not just how much of it there is. It only appears when the nearest airport's hourly report actually says so — no forecast model knows cloud shape, so it's left off rather than guessed."
        }
    }

    /// The key: short lines, read as a list.
    func howToRead(_ pressureStyle: PressureStyle,
                   _ temperatureUnit: TemperatureUnit) -> [String] {
        switch self {
        case .cloud:
            ["Empty circle — sky clear",
             "A single vertical line — 1 okta",
             "A quarter inked — 2 oktas (add the line for 3)",
             "Half inked — 4 oktas (add a horizontal line for 5)",
             "Three-quarters — 6 oktas; all but a sliver — 7",
             "Solid — overcast, 8 oktas",
             "An X — the sky is obscured, usually by fog"]
        case .wind:
            ["Half feather — 5 knots",
             "Full feather — 10 knots",
             "Solid triangle (a pennant) — 50 knots",
             "Add up whatever is on the shaft",
             "An extra ring and no shaft — calm, under 1 knot"]
        case .presentWeather:
            ["Comma — drizzle",
             "One dot — rain; three dots — heavy rain",
             "Star — snow; dot over a star — sleet",
             "Star over a triangle — snow shower",
             "Bolt — thunderstorm",
             "Two lines — mist; three lines — fog",
             "The colours are only a tint; the shape carries the meaning"]
        case .dewPoint:
            // The spreads are °C thresholds; in °F the same air is nearly
            // twice the figure, so the key converts with the slot.
            temperatureUnit == .celsius
                ? ["Within 2° of the air temperature — saturated: mist, fog or drizzle",
                   "2–5° below — muggy",
                   "5–10° below — comfortable",
                   "More than 10° below — dry air"]
                : ["Within 4° of the air temperature — saturated: mist, fog or drizzle",
                   "4–9° below — muggy",
                   "9–18° below — comfortable",
                   "More than 18° below — dry air"]
        case .pressure:
            pressureStyle.pressureKey
        case .tendency:
            pressureStyle.tendencyKey
        case .visibility:
            ["Under 1 km — fog",
             "1–4 km — mist or murk",
             "10 km or more — a clear day"]
        case .cloudGenus:
            ["A tall dome — towering cumulus (TCU): showers building",
             "A tower with a flat anvil top — cumulonimbus (CB): showers, gusts, maybe thunder",
             "Nothing drawn — the nearest report sees neither"]
        case .temperature, .pastWeather:
            []
        }
    }

    func examples(_ temperatureUnit: TemperatureUnit) -> [StationGuideExample] {
        switch self {
        case .cloud:
            [.init("Sky clear", .guide(cloud: 0), parts: [.oktas]),
             .init("2 oktas", .guide(cloud: 25), parts: [.oktas]),
             .init("4 oktas", .guide(cloud: 50), parts: [.oktas]),
             .init("5 oktas", .guide(cloud: 62), parts: [.oktas]),
             .init("7 oktas", .guide(cloud: 88), parts: [.oktas]),
             .init("Overcast", .guide(cloud: 100), parts: [.oktas])]
        case .wind:
            [.init("Calm", .guide(knots: 0), parts: [.oktas, .barb]),
             .init("5 kn from the west", .guide(knots: 5, from: 270), parts: [.oktas, .barb]),
             .init("15 kn from the north", .guide(knots: 15, from: 0), parts: [.oktas, .barb]),
             .init("50 kn from the south-west", .guide(knots: 50, from: 225), parts: [.oktas, .barb])]
        case .presentWeather:
            [.init("Drizzle", .guide(code: 53), parts: [.oktas, .presentWeather]),
             .init("Rain", .guide(code: 61), parts: [.oktas, .presentWeather]),
             .init("Heavy rain", .guide(code: 65), parts: [.oktas, .presentWeather]),
             .init("Sleet", .guide(code: 66), parts: [.oktas, .presentWeather]),
             .init("Snow", .guide(code: 73), parts: [.oktas, .presentWeather]),
             .init("Snow shower", .guide(code: 85), parts: [.oktas, .presentWeather]),
             .init("Thunderstorm", .guide(code: 95), parts: [.oktas, .presentWeather]),
             .init("Mist", .guide(code: 45), parts: [.oktas, .presentWeather]),
             .init("Fog — sky obscured, so an X", .guide(code: 48), parts: [.oktas, .presentWeather])]
        case .temperature:
            [.init("\(temperatureUnit.rounded(14)) \(temperatureUnit.symbol)",
                   .guide(temp: 14), parts: [.oktas, .temperature])]
        case .dewPoint:
            [.init("Air \(temperatureUnit.rounded(14))°, dew point "
                   + "\(temperatureUnit.rounded(11))° — muggy",
                   .guide(temp: 14, dew: 11),
                   parts: [.oktas, .temperature, .annotations]),
             .init("Air \(temperatureUnit.rounded(20))°, dew point "
                   + "\(temperatureUnit.rounded(4))° — dry",
                   .guide(temp: 20, dew: 4),
                   parts: [.oktas, .temperature, .annotations])]
        case .pressure:
            [.init("1021.6 hPa", .guide(pressure: 1021.6), parts: [.oktas, .annotations]),
             .init("998.7 hPa", .guide(pressure: 998.7), parts: [.oktas, .annotations])]
        case .tendency:
            [.init("Up 1.8 hPa, still rising", .guide(change: 1.8, tendency: .rising),
                   parts: [.oktas, .annotations]),
             .init("Down 2.4 hPa, still falling", .guide(change: -2.4, tendency: .falling),
                   parts: [.oktas, .annotations]),
             .init("Up 0.9 hPa, rise then fall", .guide(change: 0.9, tendency: .riseThenFall),
                   parts: [.oktas, .annotations])]
        case .pastWeather:
            [.init("Rain in the last six hours", .guide(past: 61), parts: [.oktas, .annotations]),
             .init("A thunderstorm earlier", .guide(past: 95), parts: [.oktas, .annotations])]
        case .visibility:
            [.init("8 km — a normal day", .guide(code: 61, visibility: 8000),
                   parts: [.oktas, .presentWeather, .annotations]),
             .init("400 m — thick fog", .guide(code: 45, visibility: 400),
                   parts: [.oktas, .presentWeather, .annotations])]
        case .cloudGenus:
            [.init("TCU — towering cumulus", .guide(genus: .toweringCumulus),
                   parts: [.oktas, .annotations]),
             .init("CB — cumulonimbus", .guide(genus: .cumulonimbus),
                   parts: [.oktas, .annotations])]
        }
    }

    /// The example that makes the best thumbnail: the one where the piece
    /// is unmistakably present (an empty circle is a poor advert for cloud
    /// cover).
    func listExample(_ temperatureUnit: TemperatureUnit) -> StationGuideExample {
        switch self {
        case .cloud, .wind:   examples(temperatureUnit)[2]
        case .presentWeather: examples(temperatureUnit)[1]
        case .cloudGenus:     examples(temperatureUnit)[1]
        default:              examples(temperatureUnit)[0]
        }
    }

    /// What this slot says on the circle in front of you — including the
    /// honest "nothing here today" cases.
    func reading(for observation: StationObservation,
                 pressureStyle: PressureStyle,
                 temperatureUnit: TemperatureUnit) -> String {
        switch self {
        case .cloud:
            return "\(observation.oktas)⁄8 — \(Self.cloudTerm(observation.oktas))"
                + (observation.skyObscured ? ", and the sky is obscured (the X)" : "")
        case .wind:
            guard observation.windSpeedKnots >= 1 else {
                return "Calm — under a knot, so the circle wears its extra ring."
            }
            return "\(observation.windText) — a shaft pointing "
                + "\(Self.compassWords(observation.compassPoint)), "
                + "drawn as \(Self.featherBreakdown(observation.windSpeedKnots))."
        case .presentWeather:
            guard let key = observation.effectivePrecip else {
                return "Nothing falling, so there's no symbol beside the circle."
            }
            return "\(Self.precipName(key)) — the symbol on the left."
        case .temperature:
            return "\(observation.roundedTemp(temperatureUnit)) \(temperatureUnit.symbol)"
        case .dewPoint:
            guard let dew = observation.dewPointRounded(temperatureUnit),
                  let dewC = observation.dewPointC else {
                return "Not available for this location."
            }
            // The wording thresholds are °C spreads; the figures shown
            // follow the chosen unit.
            let spreadC = observation.temperatureC - dewC
            let shownSpread = observation.roundedTemp(temperatureUnit) - dew
            return "\(dew) \(temperatureUnit.symbol) — \(shownSpread)° below the air "
                + "temperature: \(Self.dewTerm(spreadC))."
        case .pressure:
            guard let coded = observation.pressureCodedPPP,
                  let hPa = observation.pressureMSLhPa else {
                return "Not available for this location."
            }
            // Coded: the drawn figure, then what it works out to. Spelled
            // out, the drawn figure *is* what it works out to.
            switch pressureStyle {
            case .coded:        return String(format: "%@ — %.1f hPa", coded, hPa)
            case .hectopascals: return String(format: "%.1f hPa", hPa)
            }
        case .tendency:
            guard let pp = observation.pressureChangeCodedPP,
                  let tendency = observation.pressureTendency,
                  let change = observation.pressureChange3hPa else {
                return "Not available for this location."
            }
            switch pressureStyle {
            case .coded:
                return String(format: "%@ — %+.1f hPa over three hours, %@.",
                              pp, change, Self.tendencyTerm(tendency))
            case .hectopascals:
                return String(format: "%+.1f hPa over three hours, %@.",
                              change, Self.tendencyTerm(tendency))
            }
        case .pastWeather:
            guard let key = observation.pastWeather else {
                return "Nothing significant in the last six hours."
            }
            if let station = observation.pastWeatherStationICAO {
                return "\(Self.precipName(key)) — reported at \(station), the nearest "
                    + "airport, in the last few hours."
            }
            return "\(Self.precipName(key)) — the small symbol at the lower-right."
        case .visibility:
            return observation.visibilityText.map { "\($0)." }
                ?? "Not available for this location."
        case .cloudGenus:
            guard let genus = observation.lowCloudGenus else {
                return "Nothing reported — the nearest airport sees no CB or TCU, "
                    + "so the slot stays empty."
            }
            let name = genus == .cumulonimbus ? "Cumulonimbus" : "Towering cumulus"
            return observation.genusStationICAO.map { "\(name), reported at \($0)." }
                ?? "\(name), reported nearby."
        }
    }

    // ── Wording helpers ────────────────────────────────────────────────

    private static func cloudTerm(_ oktas: Int) -> String {
        switch oktas {
        case ..<1:  "sky clear"
        case 1...2: "a few clouds"
        case 3...4: "scattered cloud"
        case 5...7: "broken cloud"
        default:    "overcast"
        }
    }

    private static func dewTerm(_ spread: Double) -> String {
        switch spread {
        case ..<2:  "saturated air — mist, fog or drizzle weather"
        case ..<5:  "muggy"
        case ..<10: "comfortable"
        default:    "dry"
        }
    }

    private static func tendencyTerm(_ tendency: StationObservation.PressureTendency) -> String {
        switch tendency {
        case .rising:         "rising steadily"
        case .falling:        "falling steadily"
        case .steady:         "level"
        case .riseThenFall:   "up then back down"
        case .fallThenRise:   "down then back up"
        case .steadyThenRise: "level, then rising"
        case .steadyThenFall: "level, then falling"
        }
    }

    private static func precipName(_ key: StationObservation.PrecipKey) -> String {
        switch key {
        case .drizzle:    "Drizzle"
        case .rain:       "Rain"
        case .heavyRain:  "Heavy rain"
        case .sleet:      "Sleet"
        case .snow:       "Snow"
        case .snowShower: "Snow shower"
        case .thunder:    "Thunderstorm"
        case .mist:       "Mist"
        case .fog:        "Fog"
        }
    }

    private static func compassWords(_ point: String) -> String {
        let names = ["N": "north", "E": "east", "S": "south", "W": "west"]
        let spoken = point.compactMap { names[String($0)] }
        switch spoken.count {
        case 1:  return spoken[0]
        case 2:  return "\(spoken[0])-\(spoken[1])"
        default: return "\(spoken[0])-\(spoken[1])-\(spoken[2])"
        }
    }

    /// The feathers the renderer will actually draw for a given speed —
    /// same rounding to the nearest 5 knots as `drawBarb`.
    private static func featherBreakdown(_ knots: Double) -> String {
        var kt = Int((knots / 5).rounded()) * 5
        var pieces: [String] = []
        let pennants = kt / 50
        if pennants > 0 {
            pieces.append(pennants == 1 ? "a pennant (50 kn)" : "\(pennants) pennants")
            kt -= pennants * 50
        }
        let full = kt / 10
        if full > 0 {
            pieces.append(full == 1 ? "one full feather" : "\(full) full feathers")
            kt -= full * 10
        }
        if kt >= 5 { pieces.append("a half feather") }
        if pieces.isEmpty { return "a bare shaft" }
        return ListFormatter.localizedString(byJoining: pieces)
    }
}

/// The two pressure pages read differently depending on how the slots are
/// written — the guide's job is to explain what's actually on the circle,
/// so the coding rule is only taught when the circle is using it.
private extension PressureStyle {
    var pressureSummary: String {
        switch self {
        case .coded:        "Upper-right, in chart shorthand"
        case .hectopascals: "Upper-right of the circle"
        }
    }

    var pressureMeaning: String {
        switch self {
        case .coded:
            "Mean sea-level pressure, written the chart way — tenths of a millibar with the leading 9 or 10 dropped. Put back whichever one lands between 950 and 1050 mb."
        case .hectopascals:
            "Mean sea-level pressure, printed in full. A chart would code it — tenths of a millibar, leading 9 or 10 dropped — but this one prints the figure. Hectopascals and millibars are the same size, so 1021.6 hPa is 1021.6 mb."
        }
    }

    var tendencyMeaning: String {
        switch self {
        case .coded:
            "How the pressure has moved in the last three hours: the figure is the change in tenths of a millibar, and the little line is the shape of the barograph trace that got there."
        case .hectopascals:
            "How the pressure has moved in the last three hours: the figure is the change in hectopascals, and the little line is the shape of the barograph trace that got there."
        }
    }

    var pressureKey: [String] {
        switch self {
        case .coded:
            ["216 → 1021.6 hPa",
             "987 → 998.7 hPa",
             "Around 1013 hPa is average; below 1000 is a proper low",
             "Settings can print the figure in full instead"]
        case .hectopascals:
            ["Around 1013 hPa is average",
             "Below 1000 is a proper low; above 1025 a settled high",
             "A chart writes this coded — 1021.6 as 216. Settings has that too"]
        }
    }

    var tendencyKey: [String] {
        switch self {
        case .coded:
            ["The figure is tenths of a millibar: +18 means up 1.8 hPa",
             "Falling usually means weather on the way; rising means it's clearing",
             "The trace shape matters: a rise-then-fall is a front going through"]
        case .hectopascals:
            ["+1.8 means the pressure is 1.8 hPa higher than three hours ago",
             "Falling usually means weather on the way; rising means it's clearing",
             "The trace shape matters: a rise-then-fall is a front going through"]
        }
    }
}

/// One drawn illustration: a station circle showing only the parts that
/// make the point.
struct StationGuideExample: Identifiable {
    var caption: String
    var observation: StationObservation
    var parts: StationPlot.Parts
    var id: String { caption }

    init(_ caption: String, _ observation: StationObservation, parts: StationPlot.Parts) {
        self.caption = caption
        self.observation = observation
        self.parts = parts
    }
}

private extension StationObservation {
    /// A minimal observation for the guide: only the fields the example
    /// needs are set, so the annotation slots that aren't the point stay
    /// empty rather than drawing noise.
    static func guide(cloud: Double = 0, knots: Double = 0, from: Double = 225,
                      code: Int = 0, temp: Double = 14, dew: Double? = nil,
                      pressure: Double? = nil, change: Double? = nil,
                      tendency: PressureTendency? = nil, past: Int? = nil,
                      visibility: Double? = nil,
                      genus: LowCloudGenus? = nil) -> StationObservation {
        StationObservation(
            fetchedAt: .distantPast, latitude: 0, longitude: 0,
            temperatureC: temp, weatherCode: code, cloudCoverPercent: cloud,
            windSpeedKnots: knots, windFromDegrees: from,
            dewPointC: dew, pressureMSLhPa: pressure,
            pressureChange3hPa: change, pressureTendency: tendency,
            pastSignificantWeatherCode: past, visibilityMeters: visibility,
            lowCloudGenus: genus)
    }
}

// ── Views ──────────────────────────────────────────────────────────────

/// One slot explained. Presented as a sheet when a piece of the plot is
/// tapped, and pushed from the full guide list.
struct StationSlotDetail: View {
    var slot: StationSlot
    var observation: StationObservation
    @AppStorage(PressureStyleStore.key, store: PressureStyleStore.defaults)
    private var pressureStyle: PressureStyle = .default
    @AppStorage(TemperatureUnitStore.key, store: TemperatureUnitStore.defaults)
    private var temperatureUnit: TemperatureUnit = .default

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(slot.title)
                        .font(.title2.weight(.semibold))
                    Text("\(slot.code) on a weather chart")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(slot.meaning(pressureStyle, temperatureUnit))

                section("On your circle right now") {
                    Text(slot.reading(for: observation, pressureStyle: pressureStyle,
                                      temperatureUnit: temperatureUnit))
                        .font(.callout)
                }

                // The slots a setting governs carry it here as well as in
                // Settings: this is the page you're on when you find the
                // shorthand unreadable, or the unit foreign.
                if slot == .pressure || slot == .tendency {
                    section("How it's written") {
                        Picker("How it's written", selection: $pressureStyle) {
                            ForEach(PressureStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
                if slot == .temperature || slot == .dewPoint {
                    section("How it's written") {
                        Picker("How it's written", selection: $temperatureUnit) {
                            ForEach(TemperatureUnit.allCases) { unit in
                                Text(unit.title).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }

                section(slot.examples(temperatureUnit).count > 1 ? "Examples" : "Example") {
                    StationGuideExampleGrid(examples: slot.examples(temperatureUnit),
                                            pressureStyle: pressureStyle,
                                            temperatureUnit: temperatureUnit)
                }

                if !slot.howToRead(pressureStyle, temperatureUnit).isEmpty {
                    section("How to read it") {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(slot.howToRead(pressureStyle, temperatureUnit),
                                    id: \.self) { line in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("·").foregroundStyle(.tertiary)
                                    Text(line)
                                }
                            }
                        }
                        .font(.callout)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            content()
        }
    }
}

private struct StationGuideExampleGrid: View {
    var examples: [StationGuideExample]
    var pressureStyle: PressureStyle
    var temperatureUnit: TemperatureUnit

    private var tile: Double { examples.count > 4 ? 76 : 104 }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: tile + 26), spacing: 16)],
                  alignment: .leading, spacing: 16) {
            ForEach(examples) { example in
                VStack(spacing: 6) {
                    StationPlot(observation: example.observation,
                                showTemperature: example.parts.contains(.temperature),
                                fullStationModel: true,
                                pressureStyle: pressureStyle,
                                temperatureUnit: temperatureUnit,
                                parts: example.parts)
                        .frame(width: tile, height: tile)
                    Text(example.caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Every slot in one list — the way in for the pieces today's weather
/// doesn't happen to draw, and the VoiceOver-friendly route.
struct StationGuideView: View {
    var observation: StationObservation
    @AppStorage(PressureStyleStore.key, store: PressureStyleStore.defaults)
    private var pressureStyle: PressureStyle = .default
    @AppStorage(TemperatureUnitStore.key, store: TemperatureUnitStore.defaults)
    private var temperatureUnit: TemperatureUnit = .default
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Every mark around the circle is a slot on a Met Office "
                         + "surface chart. Tap any part of the plot on the main "
                         + "screen to jump straight to that piece.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Section {
                    ForEach(StationSlot.allCases) { slot in
                        NavigationLink(value: slot) {
                            HStack(spacing: 14) {
                                let example = slot.listExample(temperatureUnit)
                                StationPlot(observation: example.observation,
                                            showTemperature: example.parts.contains(.temperature),
                                            fullStationModel: true,
                                            pressureStyle: pressureStyle,
                                            temperatureUnit: temperatureUnit,
                                            parts: example.parts)
                                    .frame(width: 54, height: 54)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(slot.title)
                                    Text(slot.summary(pressureStyle))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Reading the circle")
            .navigationDestination(for: StationSlot.self) { slot in
                StationSlotDetail(slot: slot, observation: observation)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview("Guide list") {
    StationGuideView(observation: .sample)
}

#Preview("Wind") {
    StationSlotDetail(slot: .wind, observation: .sample)
}

#Preview("Cloud cover") {
    StationSlotDetail(slot: .cloud, observation: .sample)
}

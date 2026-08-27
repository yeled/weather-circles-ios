import AppIntents
import SwiftUI
import WidgetKit

struct WeatherEntry: TimelineEntry {
    let date: Date
    let observation: StationObservation
    /// Only the forecast widget reads this; the current-conditions
    /// widget's provider leaves it at the default.
    var span: ForecastSpan = .hours
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> WeatherEntry {
        WeatherEntry(date: Date(), observation: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeatherEntry) -> Void) {
        completion(WeatherEntry(date: Date(),
                                observation: WeatherStore.loadObservation() ?? .sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherEntry>) -> Void) {
        Task {
            let observation = await currentObservation()
            let entry = WeatherEntry(date: Date(), observation: observation)
            let next = Date().addingTimeInterval(30 * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

/// A pinned city wins; else the widget's own location fix; else the
/// app's last coordinate; else the original script's London default.
/// Network errors fall back to the cached observation so the circle
/// never goes blank. Shared by both widgets' providers.
private func currentObservation() async -> StationObservation {
    var latitude: Double
    var longitude: Double
    var name: String?

    if let city = CityStore.selected {
        latitude = city.latitude
        longitude = city.longitude
        name = city.name
    } else if let coordinate = await WidgetLocationProvider.requestOneShot() {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    } else if let cached = WeatherStore.loadCoordinate() {
        latitude = cached.latitude
        longitude = cached.longitude
    } else {
        latitude = 51.5074
        longitude = -0.1278
        name = "London"
    }

    // Reuse the app's reverse-geocoded name when we're still nearby.
    if name == nil, let cached = WeatherStore.loadObservation(),
       abs(cached.latitude - latitude) < 0.05,
       abs(cached.longitude - longitude) < 0.05 {
        name = cached.placeName
    }

    // No METAR leg in the widget — it never draws the full model, and
    // timeline refreshes shouldn't spend the extra request.
    if let fetched = try? await WeatherService.fetch(
        latitude: latitude, longitude: longitude, placeName: name,
        includeStationObservations: false) {
        WeatherStore.save(fetched)
        return fetched
    }
    return WeatherStore.loadObservation() ?? .sample
}

struct WeatherCirclesWidgetEntryView: View {
    var entry: WeatherEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if family == .systemSmall {
                    Color(uiColor: .systemBackground)
                } else {
                    Color.clear
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                StationPlot(observation: entry.observation, ink: .primary,
                            mono: true, showTemperature: false)
                    .padding(2)
            }
        case .accessoryRectangular:
            HStack(spacing: 6) {
                StationPlot(observation: entry.observation, ink: .primary,
                            mono: true, showTemperature: false)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(entry.observation.roundedTemp)°")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    if let highLow = entry.observation.highLowText {
                        Text(highLow)
                            .font(.caption2.monospacedDigit())
                    }
                    if let place = entry.observation.placeName {
                        Text(place)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        case .accessoryInline:
            Text("\(entry.observation.roundedTemp)° · \(entry.observation.windText) · \(entry.observation.oktas)⁄8")
        default: // .systemSmall
            VStack(spacing: 0) {
                StationPlot(observation: entry.observation,
                            haloColor: Color(uiColor: .systemBackground))
                HStack {
                    if let highLow = entry.observation.highLowText {
                        Text(highLow).monospacedDigit()
                    }
                    Spacer()
                    if let place = entry.observation.placeName {
                        Text(place)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .font(.caption2)
            }
        }
    }
}

/// What the forecast widget's four circles span: the TRMNL 2-hour slots,
/// or the daily outlook's first four days.
enum ForecastSpan: String, AppEnum {
    case hours, days

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Forecast Span"
    static let caseDisplayRepresentations: [ForecastSpan: DisplayRepresentation] = [
        .hours: "Next 8 hours",
        .days: "Next 4 days",
    ]
}

struct ForecastSpanIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Forecast Circles"
    static let description = IntentDescription("Hours or days in the four circles.")

    @Parameter(title: "Show", default: .hours)
    var span: ForecastSpan
}

struct ForecastProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WeatherEntry {
        WeatherEntry(date: Date(), observation: .sample)
    }

    func snapshot(for configuration: ForecastSpanIntent,
                  in context: Context) async -> WeatherEntry {
        WeatherEntry(date: Date(),
                     observation: WeatherStore.loadObservation() ?? .sample,
                     span: configuration.span)
    }

    func timeline(for configuration: ForecastSpanIntent,
                  in context: Context) async -> Timeline<WeatherEntry> {
        let entry = WeatherEntry(date: Date(),
                                 observation: await currentObservation(),
                                 span: configuration.span)
        return Timeline(entries: [entry],
                        policy: .after(Date().addingTimeInterval(30 * 60)))
    }
}

/// The lock screen strip is four circular slots wide and the rectangular
/// family spans two of them — the widest a single widget gets — so the
/// forecast draws its own four "spaces": four 2-hour slots or four days
/// as a row of mini circles, label above, temperature below. Add it
/// twice, one of each span, and the whole strip is circles.
struct ForecastCirclesEntryView: View {
    var entry: WeatherEntry

    var body: some View {
        content
            .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private var content: some View {
        switch entry.span {
        case .hours:
            if let slots = entry.observation.forecastSlots, !slots.isEmpty {
                row(slots.prefix(4).map { slot in
                    (slot.hourLabel, slot.asObservation(),
                     Int(slot.temperatureC.rounded()))
                })
            } else {
                fallback
            }
        case .days:
            if let days = entry.observation.dailyForecast, !days.isEmpty {
                row(days.prefix(4).map { day in
                    (Self.weekday(from: day.dateISO), day.asObservation(),
                     Int(day.highC.rounded()))
                })
            } else {
                fallback
            }
        }
    }

    private func row(_ columns: [(label: String, observation: StationObservation,
                                  temp: Int)]) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                VStack(spacing: 0) {
                    Text(column.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    StationPlot(observation: column.observation,
                                ink: .primary, mono: true,
                                showTemperature: false)
                    Text("\(column.temp)°")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// A cached observation from before the forecast arrays existed —
    /// fall back to now, rather than an empty rectangle, until the next
    /// timeline refresh brings them.
    private var fallback: some View {
        HStack(spacing: 6) {
            StationPlot(observation: entry.observation, ink: .primary,
                        mono: true, showTemperature: false)
            Text("\(entry.observation.roundedTemp)°")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Spacer(minLength: 0)
        }
    }

    // Same parsing rule as MultiDayForecastView: the location-local
    // "yyyy-MM-dd" read in UTC so no device-timezone drift can shift
    // the date.
    private static let isoDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static let weekdayOut: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    static func weekday(from iso: String) -> String {
        guard let date = isoDay.date(from: iso) else { return iso }
        return weekdayOut.string(from: date)
    }
}

struct WeatherCirclesWidget: Widget {
    let kind = "WeatherCirclesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            WeatherCirclesWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Weather Circle")
        .description("Station-model circle for current conditions — cloud oktas, wind barb, present weather — plus today's high/low.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct WeatherCirclesForecastWidget: Widget {
    let kind = "WeatherCirclesForecastWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ForecastSpanIntent.self,
                               provider: ForecastProvider()) { entry in
            ForecastCirclesEntryView(entry: entry)
        }
        .configurationDisplayName("Forecast Circles")
        .description("The next eight hours or four days as four mini circles — cloud oktas, wind barb and weather for each.")
        .supportedFamilies([.accessoryRectangular])
    }
}

@main
struct WeatherCirclesWidgetBundle: WidgetBundle {
    var body: some Widget {
        WeatherCirclesWidget()
        WeatherCirclesForecastWidget()
    }
}

#Preview(as: .accessoryCircular) {
    WeatherCirclesWidget()
} timeline: {
    WeatherEntry(date: .now, observation: .sample)
}

#Preview(as: .accessoryRectangular) {
    WeatherCirclesWidget()
} timeline: {
    WeatherEntry(date: .now, observation: .sample)
}

#Preview(as: .systemSmall) {
    WeatherCirclesWidget()
} timeline: {
    WeatherEntry(date: .now, observation: .sample)
}

#Preview(as: .accessoryRectangular) {
    WeatherCirclesForecastWidget()
} timeline: {
    WeatherEntry(date: .now, observation: .sample)
    WeatherEntry(date: .now, observation: .sample, span: .days)
}

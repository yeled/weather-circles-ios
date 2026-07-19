import SwiftUI
import WidgetKit

struct WeatherEntry: TimelineEntry {
    let date: Date
    let observation: StationObservation
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

    /// Prefer the widget's own location fix; else the app's last coordinate;
    /// else the original script's London default. Network errors fall back
    /// to the cached observation so the circle never goes blank.
    private func currentObservation() async -> StationObservation {
        var latitude: Double
        var longitude: Double
        var name: String?

        if let coordinate = await WidgetLocationProvider.requestOneShot() {
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
            includeCloudGenus: false) {
            WeatherStore.save(fetched)
            return fetched
        }
        return WeatherStore.loadObservation() ?? .sample
    }
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

@main
struct WeatherCirclesWidgetBundle: WidgetBundle {
    var body: some Widget {
        WeatherCirclesWidget()
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

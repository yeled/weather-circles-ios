import SwiftUI
import WidgetKit

struct ContentView: View {
    @StateObject private var location = LocationProvider()
    @Environment(\.scenePhase) private var scenePhase

    @State private var observation: StationObservation?
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                StationPlot(observation: observation ?? .sample,
                            haloColor: Color(uiColor: .systemBackground))
                    .padding(.horizontal, 28)
                    .opacity(observation == nil ? 0.25 : 1)
                readouts
                Spacer(minLength: 24)
                Link("Weather by Open-Meteo", destination: URL(string: "https://open-meteo.com")!)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await refresh() }
        .task(id: location.coordinate.map { "\($0.latitude),\($0.longitude)" }) {
            await refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { location.refresh() }
        }
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text(observation?.placeName ?? location.placeName ?? "—")
                .font(.title2.weight(.semibold))
            if let observation {
                Text("Updated \(observation.fetchedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(location.denied ? "Location off — showing London" : "Locating…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var readouts: some View {
        VStack(spacing: 6) {
            if let highLow = observation?.highLowText {
                Text(highLow)
                    .font(.title3.weight(.medium).monospacedDigit())
            }
            if let observation {
                Text("\(observation.windText) · \(observation.oktas)⁄8 cloud")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private func refresh() async {
        let latitude: Double
        let longitude: Double
        var name: String?
        if let coordinate = location.coordinate {
            latitude = coordinate.latitude
            longitude = coordinate.longitude
            name = location.placeName
        } else if let cached = WeatherStore.loadCoordinate() {
            latitude = cached.latitude
            longitude = cached.longitude
        } else {
            latitude = LocationProvider.fallback.latitude
            longitude = LocationProvider.fallback.longitude
            name = LocationProvider.fallback.name
        }

        do {
            var fetched = try await OpenMeteoClient.observation(
                latitude: latitude, longitude: longitude, placeName: name)
            if fetched.placeName == nil { fetched.placeName = location.placeName }
            observation = fetched
            errorText = nil
            WeatherStore.save(fetched)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorText = "Fetch failed: \(error.localizedDescription)"
            if observation == nil { observation = WeatherStore.loadObservation() }
        }
    }
}

#Preview {
    ContentView()
}

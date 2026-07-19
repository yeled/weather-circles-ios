import SwiftUI
import WidgetKit

struct ContentView: View {
    @StateObject private var location = LocationProvider()
    @Environment(\.scenePhase) private var scenePhase

    @State private var observation: StationObservation?
    @State private var errorText: String?
    @State private var selectedCity: City? = CityStore.selected
    @State private var showingCityPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                StationPlot(observation: observation ?? .sample,
                            fullStationModel: true,
                            haloColor: Color(uiColor: .systemBackground))
                    .padding(.horizontal, 28)
                    .opacity(observation == nil ? 0.25 : 1)
                readouts
                if let slots = observation?.forecastSlots, !slots.isEmpty {
                    ForecastRow(slots: slots)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
                Spacer(minLength: 24)
                Link("Weather by Open-Meteo", destination: URL(string: "https://open-meteo.com")!)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await refresh() }
        .task(id: fetchTrigger) { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && selectedCity == nil { location.refresh() }
        }
        .sheet(isPresented: $showingCityPicker) {
            CityPickerView(selected: selectedCity) { choice in
                selectedCity = choice
                CityStore.selected = choice
                if let choice { CityStore.noteVisited(choice) }
                showingCityPicker = false
                if choice == nil { location.refresh() }
            }
        }
    }

    /// Refetch when the pinned city changes, or — in follow mode — when a
    /// location fix arrives.
    private var fetchTrigger: String {
        if let city = selectedCity { return "city-\(city.id)" }
        return location.coordinate.map { "gps-\($0.latitude),\($0.longitude)" } ?? "gps-pending"
    }

    private var header: some View {
        VStack(spacing: 2) {
            Button {
                showingCityPicker = true
            } label: {
                HStack(spacing: 6) {
                    if selectedCity == nil {
                        Image(systemName: "location.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(displayName)
                        .font(.title2.weight(.semibold))
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            if let observation {
                Text("Updated \(observation.fetchedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(location.denied && selectedCity == nil
                     ? "Location off — showing London" : "Loading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var displayName: String {
        selectedCity?.name ?? observation?.placeName ?? location.placeName ?? "—"
    }

    private var readouts: some View {
        VStack(spacing: 6) {
            if let highLow = observation?.highLowText {
                Text(highLow)
                    .font(.title3.weight(.medium).monospacedDigit())
            }
            if let observation {
                Text(caption(for: observation))
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

    private func caption(for observation: StationObservation) -> String {
        var caption = "\(observation.windText) · \(observation.oktas)⁄8 cloud"
        if let genus = observation.genusText { caption += " · \(genus)" }
        return caption
    }

    private func refresh() async {
        let latitude: Double
        let longitude: Double
        var name: String?
        if let city = selectedCity {
            latitude = city.latitude
            longitude = city.longitude
            name = city.name
        } else if let coordinate = location.coordinate {
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
            var fetched = try await WeatherService.fetch(
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

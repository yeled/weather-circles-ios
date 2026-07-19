import SwiftUI
import WidgetKit

struct ContentView: View {
    @StateObject private var location = LocationProvider()
    @Environment(\.scenePhase) private var scenePhase

    @State private var observation: StationObservation?
    @State private var errorText: String?
    @State private var selectedCity: City? = CityStore.selected
    @State private var showingCityPicker = false
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        // Two vertically paged screens: swipe down from the main plot for
        // the 7-day outlook, swipe up to come back. (This gesture replaces
        // pull-to-refresh — tap the "Updated…" caption to force a fetch.)
        ScrollView {
            VStack(spacing: 0) {
                MultiDayForecastView(days: observation?.dailyForecast ?? [])
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .containerRelativeFrame(.vertical)
                mainPage
                    .containerRelativeFrame(.vertical)
            }
        }
        .scrollTargetBehavior(.paging)
        .defaultScrollAnchor(.bottom)
        .scrollIndicators(.hidden)
        .task { await refresh() }
        .onChange(of: gpsFix) { _, _ in
            // A follow-mode location fix arrived (or moved).
            if selectedCity == nil { refreshNow() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            if selectedCity == nil { location.refresh() } else { refreshNow() }
        }
        .sheet(isPresented: $showingCityPicker) {
            CityPickerView(selected: selectedCity) { choice in
                selectedCity = choice
                CityStore.selected = choice
                errorText = nil
                if let choice {
                    CityStore.noteVisited(choice)
                    // Instant swap to the city's last-known plot ("Updated
                    // X ago" stays honest); the live fetch replaces it.
                    observation = WeatherStore.loadObservation(cityID: choice.id)
                } else {
                    observation = nil
                    location.refresh()
                }
                showingCityPicker = false
                refreshNow()
            }
        }
    }

    private var mainPage: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                Image(systemName: "chevron.compact.up")
                Text("7 days")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
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
            Spacer(minLength: 12)
            Link("Weather by Open-Meteo", destination: URL(string: "https://open-meteo.com")!)
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: 560)          // keeps the plot sane on iPad
        .frame(maxWidth: .infinity)
    }

    private var gpsFix: String {
        location.coordinate.map { "\($0.latitude),\($0.longitude)" } ?? "pending"
    }

    /// What the in-flight fetch is for — lets a finished fetch check it
    /// hasn't been superseded by a newer selection before committing.
    private var selectionSignature: String {
        selectedCity.map { "city-\($0.id)" } ?? "follow"
    }

    /// Cancel any in-flight fetch and start a fresh one. Selection changes
    /// call this directly rather than relying on view-modifier diffing.
    private func refreshNow() {
        refreshTask?.cancel()
        refreshTask = Task { await refresh() }
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
                Button { refreshNow() } label: {
                    Text("Updated \(observation.fetchedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
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

        let signature = selectionSignature
        do {
            var fetched = try await WeatherService.fetch(
                latitude: latitude, longitude: longitude, placeName: name)
            guard signature == selectionSignature else { return }  // superseded
            if fetched.placeName == nil { fetched.placeName = location.placeName }
            observation = fetched
            errorText = nil
            WeatherStore.save(fetched, cityID: selectedCity?.id)
            WidgetCenter.shared.reloadAllTimelines()
        } catch is CancellationError {
            // A newer trigger (fresh GPS fix, city change) owns the UI now.
        } catch let urlError as URLError where urlError.code == .cancelled {
            // Same: superseded mid-request by a newer refresh.
        } catch {
            errorText = "Fetch failed: \(error.localizedDescription)"
            if observation == nil { observation = WeatherStore.loadObservation() }
        }
    }
}

#Preview {
    ContentView()
}

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
    @State private var explainedSlot: StationSlot?
    @State private var showingGuide = false
    @State private var showingSettings = false
    @State private var currentPage: Page? = .main
    /// The "tap the circle" nudge earns its line of screen once.
    @AppStorage("guideHintSeen") private var guideHintSeen = false
    /// Coded PPP/pp or the figures in full — see `PressureStyle`.
    @AppStorage(PressureStyleStore.key, store: PressureStyleStore.defaults)
    private var pressureStyle: PressureStyle = .default

    /// The vertical pages, in order. Tracked so the area chart can wait
    /// until it's actually on screen before spending a fetch on itself.
    private enum Page: Int, Hashable {
        case main, week, map
    }

    var body: some View {
        // Three vertically paged screens: swipe up from the main plot for
        // the 7-day outlook, again for the area chart, swipe down to come
        // back. Pull-to-refresh keeps the classic downward drag at the top
        // of the main page.
        // A page is sized to the whole window, not to the safe area, and
        // insets itself. Sized to the safe area it was 81pt shorter than
        // the window it pages through, so at the bottom of the scroll the
        // leftover had to be filled by whatever sat above — the main
        // page's footer, stranded in the status bar strip. (Nobody noticed
        // on page 1: what's above *it* is blank.)
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    page(mainPage, in: proxy)
                        .id(Page.main)
                    page(MultiDayForecastView(days: observation?.dailyForecast ?? [],
                                              placeName: displayName)
                            .frame(maxWidth: 560)
                            .frame(maxWidth: .infinity),
                         in: proxy)
                        .id(Page.week)
                    page(CountryChartView(centerLatitude: chartCenter.latitude,
                                          centerLongitude: chartCenter.longitude,
                                          placeName: displayName,
                                          isActive: currentPage == .map)
                            .frame(maxWidth: CountryChartView.maxPlateWidth)
                            .frame(maxWidth: .infinity),
                         in: proxy)
                        .id(Page.map)
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $currentPage)
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .refreshable { await refresh() }
        }
        .ignoresSafeArea()      // so the proxy reports the real insets
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
        .sheet(item: $explainedSlot) { slot in
            StationSlotDetail(slot: slot, observation: observation ?? .sample)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingGuide) {
            StationGuideView(observation: observation ?? .sample)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    private func explain(_ slot: StationSlot) {
        guideHintSeen = true
        explainedSlot = slot
    }

    /// One full-window page: the content keeps its old safe-area margins,
    /// but the page itself is as tall as the window so paging lands on it
    /// exactly, with nothing of the neighbouring page left showing.
    private func page(_ content: some View, in proxy: GeometryProxy) -> some View {
        content
            .padding(.top, windowSafeAreaInsets.top)
            .padding(.bottom, windowSafeAreaInsets.bottom)
            .frame(height: proxy.size.height)
    }

    /// The window's safe-area insets. Read from the window because the
    /// obvious source doesn't work: once the `GeometryReader` above is
    /// `.ignoresSafeArea()` — which it must be, to measure the full window
    /// — its proxy reports the insets as zero, which put the header under
    /// the status bar.
    private var windowSafeAreaInsets: EdgeInsets {
        let insets = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow?.safeAreaInsets ?? .zero
        return EdgeInsets(top: insets.top, leading: insets.left,
                          bottom: insets.bottom, trailing: insets.right)
    }

    private var mainPage: some View {
        VStack(spacing: 12) {
            header
            StationPlot(observation: observation ?? .sample,
                        fullStationModel: true,
                        pressureStyle: pressureStyle,
                        haloColor: Color(uiColor: .systemBackground),
                        highlightedSlot: explainedSlot,
                        onSelectSlot: explain)
                .padding(.horizontal, 28)
                .opacity(observation == nil ? 0.25 : 1)
            if !guideHintSeen {
                Text("Tap any part of the circle to see what it means")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            readouts
            if let slots = observation?.forecastSlots, !slots.isEmpty {
                ForecastRow(slots: slots)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }
            Spacer(minLength: 12)
            HStack(spacing: 16) {
                Button {
                    guideHintSeen = true
                    showingGuide = true
                } label: {
                    Label("What am I looking at?", systemImage: "questionmark.circle")
                }
                .buttonStyle(.plain)
                Link("Weather by Open-Meteo", destination: URL(string: "https://open-meteo.com")!)
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }
            .font(.footnote)
            .foregroundStyle(.tertiary)
            VStack(spacing: 0) {
                Text("7 days")
                Image(systemName: "chevron.compact.down")
            }
            .font(.caption2)
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

    /// Where the area chart is centred: the same point the main plot came
    /// from, so the middle circle of the lattice is the one on page one.
    /// Falls back through the same ladder `refresh()` walks.
    private var chartCenter: (latitude: Double, longitude: Double) {
        if let city = selectedCity { return (city.latitude, city.longitude) }
        if let observation { return (observation.latitude, observation.longitude) }
        if let coordinate = location.coordinate {
            return (coordinate.latitude, coordinate.longitude)
        }
        if let cached = WeatherStore.loadCoordinate() {
            return (cached.latitude, cached.longitude)
        }
        return (LocationProvider.fallback.latitude, LocationProvider.fallback.longitude)
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

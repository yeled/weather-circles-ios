import SwiftUI

/// Search sheet: current location, recents, and Open-Meteo geocoder results.
struct CityPickerView: View {
    var selected: City?
    var onSelect: (City?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [City] = []
    private let recents = CityStore.recents

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onSelect(nil)
                } label: {
                    Label("Current Location", systemImage: "location.fill")
                        .fontWeight(selected == nil ? .semibold : .regular)
                }
                if !results.isEmpty {
                    Section("Results") {
                        ForEach(results) { row($0) }
                    }
                }
                if !recents.isEmpty && query.isEmpty {
                    Section("Recent") {
                        ForEach(recents) { row($0) }
                    }
                }
            }
            .searchable(text: $query, prompt: "City name")
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                results = (try? await GeocodingClient.search(query)) ?? []
            }
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ city: City) -> some View {
        Button {
            onSelect(city)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(city.name)
                    if !city.subtitle.isEmpty {
                        Text(city.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if selected?.id == city.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .foregroundStyle(.primary)
    }
}

#Preview {
    CityPickerView(selected: nil) { _ in }
}

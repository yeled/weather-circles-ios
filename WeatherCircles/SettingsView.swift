import SwiftUI
import WidgetKit

/// The app's settings — how the pressure slots are written, and which
/// unit the temperatures wear — and each choice is shown rather than
/// described: every row draws the same observation the way picking it
/// would draw it, so you compare circles instead of parsing a sentence
/// about tenths of a millibar.
struct SettingsView: View {
    @AppStorage(PressureStyleStore.key, store: PressureStyleStore.defaults)
    private var pressureStyle: PressureStyle = .default
    @AppStorage(TemperatureUnitStore.key, store: TemperatureUnitStore.defaults)
    private var temperatureUnit: TemperatureUnit = .default
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(TemperatureUnit.allCases) { unit in
                        Button { temperatureUnit = unit } label: {
                            row(for: unit)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Temperature")
                } footer: {
                    Text("Charts — and the model underneath — think in °C. "
                         + "This changes every temperature the app writes: the "
                         + "circle, the forecasts, and the widgets.")
                }

                Section {
                    ForEach(PressureStyle.allCases) { style in
                        Button { pressureStyle = style } label: {
                            row(for: style)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Pressure")
                } footer: {
                    Text("Charts write pressure coded — tenths of a hectopascal "
                         + "with the leading 9 or 10 dropped — which is the real "
                         + "notation, and unreadable until you know the rule. "
                         + "This changes the two pressure slots only; the rest of "
                         + "the circle is unaffected.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // Pressure never reaches the widgets (they draw the plain
            // circle), but every widget writes a temperature.
            .onChange(of: temperatureUnit) {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    private func row(for unit: TemperatureUnit) -> some View {
        HStack(spacing: 14) {
            StationPlot(observation: Self.preview,
                        temperatureUnit: unit,
                        parts: [.oktas, .temperature])
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(unit.title)
                Text(unit.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .opacity(temperatureUnit == unit ? 1 : 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(temperatureUnit == unit ? [.isSelected] : [])
    }

    private func row(for style: PressureStyle) -> some View {
        HStack(spacing: 14) {
            StationPlot(observation: Self.preview,
                        showTemperature: false,
                        fullStationModel: true,
                        pressureStyle: style,
                        parts: [.oktas, .annotations])
                .frame(width: 64, height: 64)      // the figure is the point, so a size up from the guide's thumbnails
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(style.title)
                Text(style.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .opacity(pressureStyle == style ? 1 : 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(pressureStyle == style ? [.isSelected] : [])
    }

    /// One observation for every row's thumbnail; each row picks `parts`
    /// so its circle shows only the slots that row's setting governs.
    private static let preview = StationObservation(
        fetchedAt: .distantPast, latitude: 0, longitude: 0,
        temperatureC: 14, weatherCode: 0, cloudCoverPercent: 0,
        windSpeedKnots: 0, windFromDegrees: 0,
        pressureMSLhPa: 1021.6, pressureChange3hPa: 1.1, pressureTendency: .rising)
}

#Preview {
    SettingsView()
}

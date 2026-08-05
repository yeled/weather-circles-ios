import SwiftUI

/// The app's settings. One thing so far — how the pressure slots are
/// written — and the choice is shown rather than described: each row draws
/// the same observation the way picking it would draw it, so you compare
/// circles instead of parsing a sentence about tenths of a millibar.
struct SettingsView: View {
    @AppStorage(PressureStyleStore.key, store: PressureStyleStore.defaults)
    private var pressureStyle: PressureStyle = .default
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
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
        }
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

    /// Pressure and tendency only, so each row's circle shows the two
    /// slots the setting governs and nothing else.
    private static let preview = StationObservation(
        fetchedAt: .distantPast, latitude: 0, longitude: 0,
        temperatureC: 14, weatherCode: 0, cloudCoverPercent: 0,
        windSpeedKnots: 0, windFromDegrees: 0,
        pressureMSLhPa: 1021.6, pressureChange3hPa: 1.1, pressureTendency: .rising)
}

#Preview {
    SettingsView()
}

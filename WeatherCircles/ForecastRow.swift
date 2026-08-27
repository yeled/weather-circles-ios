import SwiftUI

/// TRMNL-style forecast strip: eight rolling 2-hour slots as mini station
/// circles in the plugin's 4-column grid — hour above, temperature below.
struct ForecastRow: View {
    let slots: [StationObservation.ForecastSlot]
    @AppStorage(TemperatureUnitStore.key, store: TemperatureUnitStore.defaults)
    private var temperatureUnit: TemperatureUnit = .default

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                VStack(spacing: 3) {
                    Text(slot.hourLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    StationPlot(observation: slot.asObservation(),
                                showTemperature: false,
                                temperatureUnit: temperatureUnit,
                                haloColor: Color(uiColor: .systemBackground))
                    Text("\(temperatureUnit.rounded(slot.temperatureC))°")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
            }
        }
    }
}

private func previewSlots() -> [StationObservation.ForecastSlot] {
    let codes = [1, 2, 3, 61, 63, 80, 95, 71]
    var slots: [StationObservation.ForecastSlot] = []
    for i in 0..<8 {
        let hour: Int = (14 + 2 * i) % 24
        let temp: Double = Double(18 - i)
        let cloud: Double = Double(i) * 12.5
        let wind: Double = Double(5 + i * 3)
        let direction: Double = Double(i) * 45.0
        slots.append(StationObservation.ForecastSlot(
            localHour: hour, temperatureC: temp, weatherCode: codes[i],
            cloudCoverPercent: cloud, windSpeedKnots: wind,
            windFromDegrees: direction))
    }
    return slots
}

#Preview {
    ForecastRow(slots: previewSlots()).padding()
}

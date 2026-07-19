import SwiftUI

/// The pull-down page: seven days, one honest circle each — most-severe
/// weather code, mean cloud cover, max wind with dominant direction.
struct MultiDayForecastView: View {
    let days: [StationObservation.DailyForecast]

    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 8)
            Text("Next 7 days")
                .font(.title3.weight(.semibold))
            if days.isEmpty {
                Spacer()
                Text("Loading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                Spacer(minLength: 4)
                ForEach(Array(days.enumerated()), id: \.element.dateISO) { index, day in
                    dayRow(day, isToday: index == 0)
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Image(systemName: "chevron.compact.down")
                    Text("now")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 10)
        }
        .padding(.horizontal, 24)
    }

    private func dayRow(_ day: StationObservation.DailyForecast, isToday: Bool) -> some View {
        HStack(spacing: 12) {
            Text(isToday ? "Today" : Self.weekday(from: day.dateISO))
                .font(.callout.weight(isToday ? .semibold : .regular))
                .frame(width: 56, alignment: .leading)
            StationPlot(observation: day.asObservation(),
                        showTemperature: false,
                        haloColor: Color(uiColor: .systemBackground))
                .frame(height: 54)
            Spacer(minLength: 4)
            if day.precipitationSumMM >= 0.1 {
                Text(String(format: "%.1f mm", day.precipitationSumMM))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(day.windText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .trailing)
            Text("\(Int(day.highC.rounded()))°")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
            Text("\(Int(day.lowC.rounded()))°")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 32, alignment: .trailing)
        }
    }

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

    /// Weekday from the location-local "yyyy-MM-dd" — parsed in UTC so no
    /// device-timezone drift can shift the date.
    static func weekday(from iso: String) -> String {
        guard let date = isoDay.date(from: iso) else { return iso }
        return weekdayOut.string(from: date)
    }
}

private func previewDays() -> [StationObservation.DailyForecast] {
    let codes = [3, 61, 80, 95, 2, 71, 0]
    let precip: [Double] = [0, 2.4, 5.1, 12.0, 0, 1.2, 0]
    var days: [StationObservation.DailyForecast] = []
    for i in 0..<7 {
        let date = String(format: "2026-07-%02d", 19 + i)
        let high: Double = Double(24 - i)
        let low: Double = Double(14 - i)
        let cloud: Double = Double(i) * 14.0
        let wind: Double = Double(8 + i * 4)
        let direction: Double = Double(i) * 50.0
        days.append(StationObservation.DailyForecast(
            dateISO: date, highC: high, lowC: low, weatherCode: codes[i],
            cloudCoverMeanPercent: cloud, windMaxKnots: wind,
            windDominantDegrees: direction, precipitationSumMM: precip[i]))
    }
    return days
}

#Preview {
    MultiDayForecastView(days: previewDays())
}

import Foundation

/// One fetch for everything the plot needs: Open-Meteo for the model
/// fields, plus (optionally) the nearest METAR for observed low-cloud
/// genus and past weather. The METAR leg runs concurrently and never
/// fails the fetch — if aviationweather.gov is down, both glyphs simply
/// stay off (or past weather falls back to the model's own guess).
enum WeatherService {
    static func fetch(latitude: Double, longitude: Double,
                      placeName: String? = nil,
                      includeStationObservations: Bool = true) async throws -> StationObservation {
        guard includeStationObservations else {
            return try await OpenMeteoClient.observation(
                latitude: latitude, longitude: longitude, placeName: placeName)
        }
        async let metar = MetarClient.findings(latitude: latitude, longitude: longitude)
        var observation = try await OpenMeteoClient.observation(
            latitude: latitude, longitude: longitude, placeName: placeName)
        let findings = await metar
        if let found = findings.genus {
            observation.lowCloudGenus = found.genus
            observation.genusStationICAO = found.station
        }
        if let found = findings.pastWeather {
            observation.pastWeatherMETAR = found.key
            observation.pastWeatherStationICAO = found.station
        }
        return observation
    }
}

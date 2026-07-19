import Foundation

/// One fetch for everything the plot needs: Open-Meteo for the model
/// fields, plus (optionally) the nearest METAR for observed low-cloud
/// genus. The METAR leg runs concurrently and never fails the fetch —
/// if aviationweather.gov is down, the C_L glyph simply stays off.
enum WeatherService {
    static func fetch(latitude: Double, longitude: Double,
                      placeName: String? = nil,
                      includeCloudGenus: Bool = true) async throws -> StationObservation {
        guard includeCloudGenus else {
            return try await OpenMeteoClient.observation(
                latitude: latitude, longitude: longitude, placeName: placeName)
        }
        async let genus = MetarClient.lowCloudGenus(latitude: latitude, longitude: longitude)
        var observation = try await OpenMeteoClient.observation(
            latitude: latitude, longitude: longitude, placeName: placeName)
        if let found = await genus {
            observation.lowCloudGenus = found.genus
            observation.genusStationICAO = found.station
        }
        return observation
    }
}

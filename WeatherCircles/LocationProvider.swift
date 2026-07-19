import CoreLocation
import Foundation

/// One-shot "where am I" for the app UI. Publishes the coordinate and a
/// reverse-geocoded locality name; the view falls back to London (the
/// original script's default) if authorisation is denied.
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let fallback = (latitude: 51.5074, longitude: -0.1278, name: "London")

    @Published var coordinate: CLLocationCoordinate2D?
    @Published var placeName: String?
    @Published var denied = false

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func refresh() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            denied = true
        default:
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            denied = false
            manager.requestLocation()
        case .denied, .restricted:
            denied = true
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        coordinate = location.coordinate
        WeatherStore.saveCoordinate(latitude: location.coordinate.latitude,
                                    longitude: location.coordinate.longitude)
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            self?.placeName = placemarks?.first?.locality ?? placemarks?.first?.name
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keep whatever we had; the view falls back to the cache or London.
    }
}

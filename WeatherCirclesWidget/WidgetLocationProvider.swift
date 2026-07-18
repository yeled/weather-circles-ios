import CoreLocation
import Foundation

/// One-shot location fix for the widget process. Needs the app to have
/// been granted While-Using/Always plus `NSWidgetWantsLocation` in the
/// widget's Info.plist; otherwise resolves nil and the timeline provider
/// falls back to the app's cached coordinate.
///
/// @unchecked Sendable: all mutable state (continuation, manager, cancelled)
/// is confined to the main queue — mutated only inside main.async blocks and
/// delegate callbacks from a manager created on main.
final class WidgetLocationProvider: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private static var active: WidgetLocationProvider?   // keep alive during request

    private var manager: CLLocationManager?
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?
    private var cancelled = false

    static func requestOneShot(timeout: TimeInterval = 8) async -> CLLocationCoordinate2D? {
        let provider = WidgetLocationProvider()
        active = provider
        defer { active = nil }

        return await withTaskGroup(of: CLLocationCoordinate2D?.self) { group in
            group.addTask { await provider.request() }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func request() async -> CLLocationCoordinate2D? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { cont in
                DispatchQueue.main.async {
                    if self.cancelled {
                        cont.resume(returning: nil)
                        return
                    }
                    self.continuation = cont
                    let manager = CLLocationManager()
                    self.manager = manager
                    manager.delegate = self
                    manager.desiredAccuracy = kCLLocationAccuracyKilometer
                    let status = manager.authorizationStatus
                    guard status == .authorizedWhenInUse || status == .authorizedAlways,
                          manager.isAuthorizedForWidgetUpdates else {
                        self.finish(nil)
                        return
                    }
                    manager.requestLocation()
                }
            }
        } onCancel: {
            DispatchQueue.main.async {
                self.cancelled = true
                self.finish(nil)
            }
        }
    }

    private func finish(_ coordinate: CLLocationCoordinate2D?) {
        continuation?.resume(returning: coordinate)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last?.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }

    deinit {
        continuation?.resume(returning: nil)
    }
}

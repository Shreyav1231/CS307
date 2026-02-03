import Foundation
import Combine
import CoreLocation

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let lm = CLLocationManager()

    @Published var latest: CLLocation?
    @Published var authorization: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        lm.delegate = self

        // Accuracy-first settings
        lm.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        lm.distanceFilter = kCLDistanceFilterNone
        lm.activityType = .otherNavigation
        lm.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        // Request permission if needed
        let status = lm.authorizationStatus
        authorization = status

        if status == .notDetermined {
            lm.requestWhenInUseAuthorization()
        }

        // Start updates (if not authorized yet, iOS will prompt; updates begin after approval)
        lm.startUpdatingLocation()
    }

    func stop() {
        lm.stopUpdatingLocation()
    }

    // MARK: - Delegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if authorization == .authorizedWhenInUse || authorization == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Use most recent
        guard let loc = locations.last else { return }
        latest = loc
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // If you want, you can log this later.
        // For now we just keep last known location.
    }
}


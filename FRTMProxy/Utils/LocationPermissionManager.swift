import Foundation
import CoreLocation

@MainActor
final class LocationPermissionManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationPermissionManager()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var locationServicesEnabled: Bool = CLLocationManager.locationServicesEnabled()

    private let manager = CLLocationManager()

    private override init() {
        super.init()
        manager.delegate = self
        refresh()
    }

    func refresh() {
        locationServicesEnabled = CLLocationManager.locationServicesEnabled()
        authorizationStatus = manager.authorizationStatus
    }

    func requestWhenInUseIfNeeded() {
        refresh()
        guard locationServicesEnabled else { return }
        guard authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    var hasWiFiSSIDAccess: Bool {
        guard locationServicesEnabled else { return false }
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.refresh()
        }
    }
}


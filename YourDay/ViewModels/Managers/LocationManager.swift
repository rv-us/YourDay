//
//  LocationManager.swift
//  YourDay
//
//  Created by Ruthwika Gajjala on 5/20/25.
//

import Foundation
import CoreLocation

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var currentLocation: CLLocation?

    /// Completions waiting on the user's answer to the permission dialog.
    /// Fulfilled from locationManagerDidChangeAuthorization — the dialog can
    /// stay up indefinitely, so polling the status on a timer reports a false
    /// "denied" before the user has answered.
    private var pendingAuthCompletions: [(Bool) -> Void] = []

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 50  // meters
        requestPermissions { _ in }
    }

    func requestPermissions(completion: @escaping (Bool) -> Void) {
        let status = locationManager.authorizationStatus
        switch status {
        case .notDetermined:
            pendingAuthCompletions.append(completion)
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways:
            locationManager.startUpdatingLocation()
            completion(true)
        case .authorizedWhenInUse:
            // Geofencing needs Always — surface the one-time upgrade prompt
            // if iOS still allows it, but report granted for the current level.
            locationManager.startUpdatingLocation()
            locationManager.requestAlwaysAuthorization()
            completion(true)
        default:
            completion(false)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }

        let granted = status == .authorizedAlways || status == .authorizedWhenInUse
        if granted {
            manager.startUpdatingLocation()
        }

        let completions = pendingAuthCompletions
        pendingAuthCompletions.removeAll()
        for completion in completions {
            completion(granted)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        DispatchQueue.main.async {
            self.currentLocation = latest
        }
    }

}

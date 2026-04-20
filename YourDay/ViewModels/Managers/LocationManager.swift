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
            locationManager.requestWhenInUseAuthorization()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let authStatus = self.locationManager.authorizationStatus
                let granted = authStatus == .authorizedAlways || authStatus == .authorizedWhenInUse
                completion(granted)
                if granted {
                    self.locationManager.startUpdatingLocation()
                }
            }
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
            completion(true)
        default:
            completion(false)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        DispatchQueue.main.async {
            self.currentLocation = latest
            NotificationManager.shared.handleLocationUpdate(location: latest, taskSummary: self.cachedTaskSummary)
        }
    }

    /// Call from a view that has task data to keep location reminders context-aware.
    func updateTaskSummary(_ summary: String) {
        cachedTaskSummary = summary
    }

    private var cachedTaskSummary: String = ""
}

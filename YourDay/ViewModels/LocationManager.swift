//
//  LocationManager.swift
//  YourDay
//
//  Created by Ruthwika Gajjala on 5/20/25.
//

import Foundation
import CoreLocation
import UserNotifications

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var currentLocation: CLLocation?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 50  // meters
        requestPermissions()
    }

    func requestPermissions() {
        locationManager.requestAlwaysAuthorization()
        locationManager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        DispatchQueue.main.async {
            self.currentLocation = latest
            self.handleLocationUpdate(location: latest)
        }
    }

    private func handleLocationUpdate(location: CLLocation) {
        let locationRemindersEnabled = UserDefaults.standard.bool(forKey: locationRemindersEnabledKey)
        let notificationsEnabled = UserDefaults.standard.bool(forKey: notificationsEnabledKey)

        guard notificationsEnabled && locationRemindersEnabled else { return }

        let maxReminders = UserDefaults.standard.integer(forKey: extraNotificationsKey)
        resetDailyReminderCountIfNeeded()
        let sentCount = UserDefaults.standard.integer(forKey: "totalExtraRemindersSentToday")

        guard sentCount < maxReminders else { return }

        // Basic logic: notify user if they haven't moved much in a while
        // (you can expand this to be smarter)
        scheduleLocationNotification()

        UserDefaults.standard.set(sentCount + 1, forKey: "totalExtraRemindersSentToday")
    }

    private func scheduleLocationNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Reminder Based on Your Location"
        content.body = "Looks like you've been in one place a while — consider tackling a task!"
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    private func resetDailyReminderCountIfNeeded() {
        print("Reset called. Count set to 0.")
        let calendar = Calendar.current
        let lastReset = UserDefaults.standard.object(forKey: "lastReminderReset") as? Date ?? .distantPast
        if !calendar.isDateInToday(lastReset) {
            UserDefaults.standard.set(0, forKey: "totalExtraRemindersSentToday")
            UserDefaults.standard.set(Date(), forKey: "lastReminderReset")
        }
    }
}

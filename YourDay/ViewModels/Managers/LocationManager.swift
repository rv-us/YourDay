//
//  LocationManager.swift
//  YourDay
//
//  Created by Ruthwika Gajjala on 5/20/25.
//

import Foundation
import CoreLocation
import UserNotifications
import GoogleGenerativeAI

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
            self.handleLocationUpdate(location: latest)
        }
    }

    /// Call from a view that has task data to keep location reminders context-aware.
    func updateTaskSummary(_ summary: String) {
        cachedTaskSummary = summary
    }

    private var cachedTaskSummary: String = ""

    private func handleLocationUpdate(location: CLLocation) {
        let locationRemindersEnabled = UserDefaults.standard.object(forKey: locationRemindersEnabledKey) as? Bool ?? true
        let notificationsEnabled = UserDefaults.standard.object(forKey: notificationsEnabledKey) as? Bool ?? true

        guard notificationsEnabled && locationRemindersEnabled else { return }

        let maxReminders = UserDefaults.standard.object(forKey: extraNotificationsKey) as? Int ?? 3
        resetDailyReminderCountIfNeeded()
        let sentCount = UserDefaults.standard.integer(forKey: "totalExtraRemindersSentToday")
        guard sentCount < maxReminders else { return }

        let taskSummary = cachedTaskSummary.isEmpty ? "No tasks" : cachedTaskSummary
        let idleTime = 0 // TODO: derive from last app interaction if desired

        evaluateWithGemini(location: location, taskSummary: taskSummary, idleTime: idleTime) { shouldSend, message in
            if shouldSend, let msg = message {
                self.scheduleLLMBasedNotification(message: msg)
                UserDefaults.standard.set(sentCount + 1, forKey: "totalExtraRemindersSentToday")
            }
        }
    }

    private func scheduleLLMBasedNotification(message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Smart Reminder"
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func resetDailyReminderCountIfNeeded() {
        let calendar = Calendar.current
        let lastReset = UserDefaults.standard.object(forKey: "lastReminderReset") as? Date ?? .distantPast
        if !calendar.isDateInToday(lastReset) {
            UserDefaults.standard.set(0, forKey: "totalExtraRemindersSentToday")
            UserDefaults.standard.set(Date(), forKey: "lastReminderReset")
        }
    }

    private func evaluateWithGemini(location: CLLocation, taskSummary: String, idleTime: Int, completion: @escaping (Bool, String?) -> Void) {
        let config = GenerationConfig(temperature: 0.7)
        // Updated to Gemini 2.5 Flash Lite for improved responses
        let model = GenerativeModel(name: "gemini-2.5-flash", apiKey: "AIzaSyBCi21xH2HVnaSgZebq_WWwsD-553mmVlY", generationConfig: config)

        let prompt = """
        The user is currently at coordinates: \(location.coordinate.latitude), \(location.coordinate.longitude).
        They have been idle for \(idleTime) minutes.
        Their tasks for today include: \(taskSummary).

        Based on this context, should we notify them with a motivational or context-aware reminder?
        Reply in JSON format like: { "sendNotification": true, "message": "Time to focus on your report!" }
        """

        Task {
            do {
                let response = try await model.generateContent(prompt)
                if let text = response.text {
                    if let data = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let send = json["sendNotification"] as? Bool {
                        completion(send, json["message"] as? String)
                    } else {
                        print("Gemini response parse failed. Raw text: \(text)")
                        completion(false, nil)
                    }
                } else {
                    completion(false, nil)
                }
            } catch {
                print("Gemini evaluation failed: \(error)")
                completion(false, nil)
            }
        }
    }
}

//
//  GoogleCalendarManager.swift
//  YourDay
//
//  Utility class for Google Calendar write operations
//

import Foundation
import UIKit
import GoogleSignIn
import FirebaseCore

class GoogleCalendarManager {
    static let shared = GoogleCalendarManager()
    
    private init() {
        // Restore sign-in state on initialization
        restoreSignInState()
    }
    
    // MARK: - Sign-In State Management
    
    /// Restores Google Sign-In state if user was previously signed in
    private func restoreSignInState() {
        // Configure Google Sign-In if not already configured
        if GIDSignIn.sharedInstance.configuration == nil {
            guard let clientID = FirebaseApp.app()?.options.clientID else {
                print("GoogleCalendarManager: Firebase client ID not found")
                return
            }
            let config = GIDConfiguration(clientID: clientID)
            GIDSignIn.sharedInstance.configuration = config
        }
        
        // Restore previous sign-in session
        // The Google Sign-In SDK automatically persists tokens, so we just need to restore the session
        GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
            if let error = error {
                print("GoogleCalendarManager: Failed to restore previous sign-in: \(error.localizedDescription)")
            } else if let user = user {
                print("GoogleCalendarManager: Successfully restored sign-in for user: \(user.profile?.email ?? "unknown")")
            }
        }
    }
    
    /// Checks if user is currently signed in (with or without calendar scope)
    func isSignedIn() -> Bool {
        return GIDSignIn.sharedInstance.currentUser != nil
    }
    
    // MARK: - Permission Management
    
    func checkCalendarWritePermission() -> Bool {
        guard let user = GIDSignIn.sharedInstance.currentUser else { return false }
        let calendarScope = "https://www.googleapis.com/auth/calendar"
        return user.grantedScopes?.contains(calendarScope) ?? false
    }
    
    func requestCalendarWritePermission(completion: @escaping (Bool, Error?) -> Void) {
        // First, try to restore previous sign-in if not already signed in
        if GIDSignIn.sharedInstance.currentUser == nil {
            restoreSignInState()
            
            // Wait a moment for restore to complete, then check again
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.continueRequestingCalendarPermission(completion: completion)
            }
            return
        }
        
        continueRequestingCalendarPermission(completion: completion)
    }
    
    private func continueRequestingCalendarPermission(completion: @escaping (Bool, Error?) -> Void) {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            completion(false, NSError(domain: "GoogleCalendarManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not signed in. Please sign in with Google first."]))
            return
        }
        
        let calendarScope = "https://www.googleapis.com/auth/calendar"
        
        // Check if permission already granted
        if checkCalendarWritePermission() {
            completion(true, nil)
            return
        }
        
        guard let presentingViewController = getRootViewController() else {
            completion(false, NSError(domain: "GoogleCalendarManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not present sign-in"]))
            return
        }
        
        // Request additional scope
        user.addScopes([calendarScope], presenting: presentingViewController) { result, error in
            if let error = error {
                completion(false, error)
                return
            }
            
            if result != nil {
                // Refresh tokens to ensure we have the new scope
                user.refreshTokensIfNeeded { refreshedUser, refreshError in
                    if refreshError != nil {
                        completion(false, refreshError)
                    } else {
                        completion(true, nil)
                    }
                }
            } else {
                completion(false, NSError(domain: "GoogleCalendarManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to grant calendar write permission"]))
            }
        }
    }
    
    /// Ensures the user is signed in to Google and has granted the Calendar API scope (read/write).
    /// Presents sign-in or scope UI on the key window when needed. Always calls `completion` on the main queue.
    func ensureCalendarWriteAccess(completion: @escaping (Result<Void, Error>) -> Void) {
        if Thread.isMainThread {
            performEnsureCalendarWriteAccess(completion: completion)
        } else {
            DispatchQueue.main.async {
                self.performEnsureCalendarWriteAccess(completion: completion)
            }
        }
    }
    
    private func performEnsureCalendarWriteAccess(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            completion(.failure(NSError(domain: "GoogleCalendarManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Google Sign-In is not configured."])))
            return
        }
        if GIDSignIn.sharedInstance.configuration == nil {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
        
        if checkCalendarWritePermission() {
            completion(.success(()))
            return
        }
        
        guard let presenting = getRootViewController() else {
            completion(.failure(NSError(domain: "GoogleCalendarManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not show sign-in. Try again after closing other sheets."])))
            return
        }
        
        let calendarScope = "https://www.googleapis.com/auth/calendar"
        
        func finishAfterScopeGrant(for user: GIDGoogleUser) {
            user.refreshTokensIfNeeded { _, refreshError in
                DispatchQueue.main.async {
                    if self.checkCalendarWritePermission() {
                        completion(.success(()))
                    } else if let refreshError {
                        completion(.failure(refreshError))
                    } else {
                        completion(.failure(NSError(domain: "GoogleCalendarManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Calendar access was not granted."])))
                    }
                }
            }
        }
        
        func requestScopes(for user: GIDGoogleUser) {
            user.addScopes([calendarScope], presenting: presenting) { _, error in
                DispatchQueue.main.async {
                    if let error = error {
                        completion(.failure(error))
                        return
                    }
                    finishAfterScopeGrant(for: user)
                }
            }
        }
        
        if let user = GIDSignIn.sharedInstance.currentUser {
            requestScopes(for: user)
            return
        }
        
        GIDSignIn.sharedInstance.restorePreviousSignIn { _, _ in
            DispatchQueue.main.async {
                if let user = GIDSignIn.sharedInstance.currentUser {
                    if self.checkCalendarWritePermission() {
                        completion(.success(()))
                    } else {
                        requestScopes(for: user)
                    }
                } else {
                    GIDSignIn.sharedInstance.signIn(withPresenting: presenting, hint: nil, additionalScopes: [calendarScope]) { _, error in
                        DispatchQueue.main.async {
                            if let error = error {
                                completion(.failure(error))
                                return
                            }
                            if self.checkCalendarWritePermission() {
                                completion(.success(()))
                            } else {
                                completion(.failure(NSError(domain: "GoogleCalendarManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Calendar access was not granted."])))
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Event Creation
    
    func createCalendarEvent(title: String, start: Date, end: Date, description: String? = nil, location: String? = nil, recurrence: [String]? = nil, completion: @escaping (String?, Error?) -> Void) {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            completion(nil, NSError(domain: "GoogleCalendarManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not signed in"]))
            return
        }
        
        let accessToken = user.accessToken.tokenString
        guard !accessToken.isEmpty else {
            completion(nil, NSError(domain: "GoogleCalendarManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Access token is empty"]))
            return
        }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        
        var eventData: [String: Any] = [
            "summary": title,
            "start": [
                "dateTime": formatter.string(from: start),
                "timeZone": TimeZone.current.identifier
            ],
            "end": [
                "dateTime": formatter.string(from: end),
                "timeZone": TimeZone.current.identifier
            ]
        ]
        
        if let description = description {
            eventData["description"] = description
        }
        
        if let location = location {
            eventData["location"] = location
        }
        
        if let recurrence = recurrence, !recurrence.isEmpty {
            eventData["recurrence"] = recurrence
        }
        
        guard let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events") else {
            completion(nil, NSError(domain: "GoogleCalendarManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: eventData)
        } catch {
            completion(nil, error)
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            guard let data = data else {
                completion(nil, NSError(domain: "GoogleCalendarManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"]))
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let eventId = json["id"] as? String {
                            completion(eventId, nil)
                        } else {
                            completion(nil, NSError(domain: "GoogleCalendarManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse event ID"]))
                        }
                    } catch {
                        completion(nil, error)
                    }
                } else {
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    completion(nil, NSError(domain: "GoogleCalendarManager", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP Error \(httpResponse.statusCode): \(errorMessage)"]))
                }
            } else {
                completion(nil, NSError(domain: "GoogleCalendarManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
            }
        }.resume()
    }
    
    /// Updates an existing primary-calendar event (same payload shape as create). `completion` returns the same `eventId` on success.
    func updateCalendarEvent(eventId: String, title: String, start: Date, end: Date, description: String? = nil, location: String? = nil, recurrence: [String]? = nil, completion: @escaping (String?, Error?) -> Void) {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            completion(nil, NSError(domain: "GoogleCalendarManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not signed in"]))
            return
        }
        
        let accessToken = user.accessToken.tokenString
        guard !accessToken.isEmpty else {
            completion(nil, NSError(domain: "GoogleCalendarManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Access token is empty"]))
            return
        }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        
        var eventData: [String: Any] = [
            "summary": title,
            "start": [
                "dateTime": formatter.string(from: start),
                "timeZone": TimeZone.current.identifier
            ],
            "end": [
                "dateTime": formatter.string(from: end),
                "timeZone": TimeZone.current.identifier
            ]
        ]
        
        if let description = description {
            eventData["description"] = description
        }
        
        if let location = location {
            eventData["location"] = location
        }
        
        if let recurrence = recurrence, !recurrence.isEmpty {
            eventData["recurrence"] = recurrence
        }
        
        let pathId = eventId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? eventId
        guard let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events/\(pathId)") else {
            completion(nil, NSError(domain: "GoogleCalendarManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: eventData)
        } catch {
            completion(nil, error)
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            guard let data = data else {
                completion(nil, NSError(domain: "GoogleCalendarManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"]))
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let returnedId = json["id"] as? String {
                            completion(returnedId, nil)
                        } else {
                            completion(nil, NSError(domain: "GoogleCalendarManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse event ID"]))
                        }
                    } catch {
                        completion(nil, error)
                    }
                } else {
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    completion(nil, NSError(domain: "GoogleCalendarManager", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP Error \(httpResponse.statusCode): \(errorMessage)"]))
                }
            } else {
                completion(nil, NSError(domain: "GoogleCalendarManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
            }
        }.resume()
    }
    
    /// Permanently removes an event from the user’s primary calendar. `404` is treated as success (already gone).
    func deleteCalendarEvent(eventId: String, completion: @escaping (Error?) -> Void) {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            completion(NSError(domain: "GoogleCalendarManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not signed in"]))
            return
        }
        let accessToken = user.accessToken.tokenString
        guard !accessToken.isEmpty else {
            completion(NSError(domain: "GoogleCalendarManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Access token is empty"]))
            return
        }
        let pathId = eventId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? eventId
        guard let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events/\(pathId)") else {
            completion(NSError(domain: "GoogleCalendarManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(error)
                return
            }
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 204 || httpResponse.statusCode == 200 {
                    completion(nil)
                } else if httpResponse.statusCode == 404 {
                    completion(nil)
                } else {
                    completion(NSError(domain: "GoogleCalendarManager", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP Error \(httpResponse.statusCode)"]))
                }
            } else {
                completion(NSError(domain: "GoogleCalendarManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
            }
        }.resume()
    }
    
    /// Deletes events one after another. Used when merging several separately scheduled tasks into one block.
    func deleteCalendarEventsSequentially(_ eventIds: [String], completion: @escaping (Error?) -> Void) {
        let unique = Array(Set(eventIds.filter { !$0.isEmpty }))
        func deleteAt(_ index: Int) {
            if index >= unique.count {
                completion(nil)
                return
            }
            deleteCalendarEvent(eventId: unique[index]) { err in
                if let err = err {
                    completion(err)
                    return
                }
                deleteAt(index + 1)
            }
        }
        deleteAt(0)
    }
    
    func createRecurringEvent(title: String, startTime: Date, daysOfWeek: [String], endDate: Date? = nil, description: String? = nil, location: String? = nil, completion: @escaping (String?, Error?) -> Void) {
        // Calculate end time (default to 1 hour after start)
        let endTime = Calendar.current.date(byAdding: .hour, value: 1, to: startTime) ?? startTime.addingTimeInterval(3600)
        
        // Build RRULE
        let byDay = daysOfWeek.joined(separator: ",")
        var rrule = "FREQ=WEEKLY;BYDAY=\(byDay)"
        
        if let endDate = endDate {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            rrule += ";UNTIL=\(formatter.string(from: endDate))"
        }
        
        createCalendarEvent(title: title, start: startTime, end: endTime, description: description, location: location, recurrence: [rrule], completion: completion)
    }
    
    // MARK: - Helper Methods
    
    private func getRootViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return nil
        }
        var currentViewController = rootViewController
        while let presentedController = currentViewController.presentedViewController {
            currentViewController = presentedController
        }
        return currentViewController
    }
}


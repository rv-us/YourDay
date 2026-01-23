//
//  GoogleCalendarView.swift
//  YourDay
//
//  Google Calendar Integration View - Displays Google Calendar events
//

import SwiftUI
import GoogleSignIn
import FirebaseCore
import Foundation

struct GoogleCalendarEvent: Identifiable, Codable {
    let id: String
    let summary: String
    let start: EventDateTime
    let end: EventDateTime?
    let description: String?
    let location: String?
    let htmlLink: String?
    
    struct EventDateTime: Codable {
        let date: String?
        let dateTime: String?
        let timeZone: String?
        
        var startDate: Date? {
            if let dateTime = dateTime {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return formatter.date(from: dateTime) ?? ISO8601DateFormatter().date(from: dateTime)
            } else if let date = date {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                return formatter.date(from: date)
            }
            return nil
        }
    }
}

struct GoogleCalendarView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var loginViewModel = LoginViewModel()
    
    @State private var events: [GoogleCalendarEvent] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isAuthenticated = false
    @State private var selectedDate = Date()
    @State private var showingDatePicker = false
    
    private var todayEvents: [GoogleCalendarEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        return events.filter { event in
            guard let eventDate = event.start.startDate else { return false }
            return eventDate >= startOfDay && eventDate < endOfDay
        }.sorted { event1, event2 in
            guard let date1 = event1.start.startDate, let date2 = event2.start.startDate else { return false }
            return date1 < date2
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with date selector
                VStack(spacing: 10) {
                    HStack {
                        Button(action: {
                            selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                            fetchEvents()
                        }) {
                            Image(systemName: "chevron.left")
                                .foregroundColor(dynamicPrimaryColor)
                                .font(.title3)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            showingDatePicker = true
                        }) {
                            VStack(spacing: 4) {
                                Text(selectedDate, style: .date)
                                    .font(.headline)
                                    .foregroundColor(dynamicTextColor)
                                if Calendar.current.isDateInToday(selectedDate) {
                                    Text("Today")
                                        .font(.caption)
                                        .foregroundColor(dynamicSecondaryTextColor)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                            fetchEvents()
                        }) {
                            Image(systemName: "chevron.right")
                                .foregroundColor(dynamicPrimaryColor)
                                .font(.title3)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    
                    Button(action: {
                        selectedDate = Date()
                        fetchEvents()
                    }) {
                        Text("Go to Today")
                            .font(.caption)
                            .foregroundColor(dynamicPrimaryColor)
                    }
                    .padding(.bottom, 8)
                }
                .background(dynamicSecondaryBackgroundColor)
                
                // Content
                if isLoading {
                    Spacer()
                    ProgressView("Loading calendar events...")
                        .progressViewStyle(CircularProgressViewStyle(tint: dynamicPrimaryColor))
                        .scaleEffect(1.2)
                    Spacer()
                } else if let error = errorMessage {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(dynamicDestructiveColor)
                        Text(error)
                            .foregroundColor(dynamicTextColor)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        if !isAuthenticated {
                            Button(action: authenticateWithGoogle) {
                                HStack {
                                    Image(systemName: "person.circle.fill")
                                    Text("Sign in with Google")
                                }
                                .padding()
                                .background(dynamicPrimaryColor)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                        } else {
                            Button(action: fetchEvents) {
                                Text("Retry")
                                    .padding()
                                    .background(dynamicPrimaryColor)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                        }
                    }
                    Spacer()
                } else if todayEvents.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "calendar")
                            .font(.largeTitle)
                            .foregroundColor(dynamicSecondaryTextColor)
                        Text("No events scheduled for this day")
                            .foregroundColor(dynamicSecondaryTextColor)
                        Text("Your Google Calendar events will appear here")
                            .font(.caption)
                            .foregroundColor(dynamicSecondaryTextColor)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(todayEvents) { event in
                                CalendarEventCard(event: event)
                            }
                        }
                        .padding()
                    }
                }
            }
            .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Google Calendar")
                        .fontWeight(.bold)
                        .foregroundColor(dynamicTextColor)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button(action: fetchEvents) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(dynamicPrimaryColor)
                        }
                        Button("Done") {
                            dismiss()
                        }
                        .foregroundColor(dynamicPrimaryColor)
                    }
                }
            }
            .sheet(isPresented: $showingDatePicker) {
                DatePicker("Select Date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .onChange(of: selectedDate) { _, _ in
                        showingDatePicker = false
                        fetchEvents()
                    }
            }
            .onAppear {
                checkAuthentication()
                if isAuthenticated {
                    fetchEvents()
                }
            }
        }
        .navigationViewStyle(.stack)
    }
    
    private func checkAuthentication() {
        if let user = GIDSignIn.sharedInstance.currentUser {
            print("✅ [GoogleCalendar] User is authenticated")
            print("   Email: \(user.profile?.email ?? "unknown")")
            print("   Name: \(user.profile?.name ?? "unknown")")
            if let scopes = user.grantedScopes {
                print("   Granted scopes: \(scopes.joined(separator: ", "))")
            } else {
                print("   No granted scopes found")
            }
            isAuthenticated = true
        } else {
            print("❌ [GoogleCalendar] User is not authenticated")
            isAuthenticated = false
            errorMessage = "Please sign in with Google to view your calendar events"
        }
    }
    
    private func authenticateWithGoogle() {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            errorMessage = "Google Sign-In not configured"
            return
        }
        
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        guard let presentingViewController = getRootViewController() else {
            errorMessage = "Could not present sign-in"
            return
        }
        
        // Request calendar scope during sign-in
        let calendarScope = "https://www.googleapis.com/auth/calendar.readonly"
        let additionalScopes = [calendarScope]
        
        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController, hint: nil, additionalScopes: additionalScopes) { [self] signInResult, error in
            if let error = error {
                errorMessage = "Sign-in error: \(error.localizedDescription)"
                return
            }
            
            if signInResult != nil {
                isAuthenticated = true
                errorMessage = nil
                fetchEvents()
            }
        }
    }
    
    private func fetchEvents() {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            print("❌ [GoogleCalendar] Cannot fetch events - user not signed in")
            errorMessage = "Not signed in with Google"
            isAuthenticated = false
            return
        }
        
        print("📅 [GoogleCalendar] Starting fetchEvents()")
        
        isAuthenticated = true
        isLoading = true
        errorMessage = nil
        
        // Request calendar scope if not already granted
        let calendarScope = "https://www.googleapis.com/auth/calendar.readonly"
        if let grantedScopes = user.grantedScopes, !grantedScopes.contains(calendarScope) {
            print("⚠️ [GoogleCalendar] Calendar scope not granted. Requesting scope: \(calendarScope)")
            user.addScopes([calendarScope], presenting: getRootViewController()!) { result, error in
                if let error = error {
                    print("❌ [GoogleCalendar] Failed to request calendar scope: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.errorMessage = "Failed to request calendar access: \(error.localizedDescription)"
                        self.isLoading = false
                    }
                    return
                }
                print("✅ [GoogleCalendar] Calendar scope granted successfully")
                // Refresh the token after adding scopes
                user.refreshTokensIfNeeded { user, error in
                    if let error = error {
                        print("❌ [GoogleCalendar] Failed to refresh token after scope grant: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            self.errorMessage = "Failed to refresh token: \(error.localizedDescription)"
                            self.isLoading = false
                        }
                        return
                    }
                    print("✅ [GoogleCalendar] Token refreshed after scope grant")
                    self.performFetchEvents()
                }
            }
        } else {
            print("✅ [GoogleCalendar] Calendar scope already granted")
            // Refresh token to ensure it's valid
            user.refreshTokensIfNeeded { user, error in
                if let error = error {
                    print("❌ [GoogleCalendar] Failed to refresh token: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.errorMessage = "Failed to refresh token: \(error.localizedDescription)"
                        self.isLoading = false
                    }
                    return
                }
                print("✅ [GoogleCalendar] Token refreshed successfully")
                self.performFetchEvents()
            }
        }
    }
    
    private func performFetchEvents() {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            DispatchQueue.main.async {
                self.errorMessage = "Not signed in"
                self.isLoading = false
            }
            return
        }
        
        print("📅 [GoogleCalendar] Starting to fetch events...")
        print("📅 [GoogleCalendar] User email: \(user.profile?.email ?? "unknown")")
        print("📅 [GoogleCalendar] User name: \(user.profile?.name ?? "unknown")")
        
        // Get fresh access token
        let accessToken = user.accessToken.tokenString
        
        // Verify token is not empty
        guard !accessToken.isEmpty else {
            print("❌ [GoogleCalendar] Access token is empty!")
            DispatchQueue.main.async {
                self.errorMessage = "Access token is empty. Please sign in again."
                self.isLoading = false
            }
            return
        }
        
        print("✅ [GoogleCalendar] Access token obtained (length: \(accessToken.count))")
        
        // First, fetch the list of available calendars
        fetchAvailableCalendars(accessToken: accessToken) { calendars in
            
            if let calendars = calendars {
                print("📋 [GoogleCalendar] Available calendars:")
                for calendar in calendars {
                    print("   - \(calendar.summary ?? "Unknown") (ID: \(calendar.id ?? "unknown"), Primary: \(calendar.primary == true ? "Yes" : "No"))")
                }
            }
            
            // Now fetch events from primary calendar
            self.fetchEventsFromCalendar(calendarId: "primary", accessToken: accessToken)
        }
    }
    
    private func fetchAvailableCalendars(accessToken: String, completion: @escaping ([CalendarListEntry]?) -> Void) {
        guard let url = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList") else {
            print("❌ [GoogleCalendar] Invalid calendar list URL")
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "GET"
        
        print("📋 [GoogleCalendar] Fetching calendar list from: \(url.absoluteString)")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ [GoogleCalendar] Error fetching calendar list: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let data = data else {
                print("❌ [GoogleCalendar] No data received for calendar list")
                completion(nil)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📋 [GoogleCalendar] Calendar list response status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let items = json["items"] as? [[String: Any]] {
                            let calendars = items.compactMap { CalendarListEntry(from: $0) }
                            print("✅ [GoogleCalendar] Successfully fetched \(calendars.count) calendars")
                            completion(calendars)
                        } else {
                            print("⚠️ [GoogleCalendar] Could not parse calendar list response")
                            completion(nil)
                        }
                    } catch {
                        print("❌ [GoogleCalendar] Error parsing calendar list: \(error)")
                        completion(nil)
                    }
                } else {
                    print("❌ [GoogleCalendar] Calendar list HTTP error: \(httpResponse.statusCode)")
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("   Response: \(jsonString)")
                    }
                    completion(nil)
                }
            }
        }.resume()
    }
    
    private func fetchEventsFromCalendar(calendarId: String, accessToken: String) {
        print("📅 [GoogleCalendar] Fetching events from calendar: '\(calendarId)'")
        print("📅 [GoogleCalendar] Selected date: \(selectedDate)")
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        print("📅 [GoogleCalendar] Date range: \(startOfDay) to \(endOfDay)")
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timeMin = formatter.string(from: startOfDay)
        let timeMax = formatter.string(from: endOfDay)
        
        print("📅 [GoogleCalendar] ISO8601 timeMin: \(timeMin)")
        print("📅 [GoogleCalendar] ISO8601 timeMax: \(timeMax)")
        
        // URL encode the parameters properly
        var urlComponents = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendarId)/events")!
        urlComponents.queryItems = [
            URLQueryItem(name: "timeMin", value: timeMin),
            URLQueryItem(name: "timeMax", value: timeMax),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime")
        ]
        
        guard let url = urlComponents.url else {
            print("❌ [GoogleCalendar] Invalid URL")
            DispatchQueue.main.async {
                self.errorMessage = "Invalid URL"
                self.isLoading = false
            }
            return
        }
        
        print("📅 [GoogleCalendar] Request URL: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "GET"
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    print("❌ [GoogleCalendar] Network error: \(error.localizedDescription)")
                    self.errorMessage = "Failed to fetch events: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    print("❌ [GoogleCalendar] No data received")
                    self.errorMessage = "No data received"
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("📅 [GoogleCalendar] HTTP Response Status: \(httpResponse.statusCode)")
                    
                    if httpResponse.statusCode == 401 {
                        print("⚠️ [GoogleCalendar] 401 Unauthorized - Token may be expired")
                        // Token expired or invalid - try to refresh
                        if let user = GIDSignIn.sharedInstance.currentUser {
                            user.refreshTokensIfNeeded { refreshedUser, refreshError in
                                if refreshError == nil, refreshedUser != nil {
                                    print("✅ [GoogleCalendar] Token refreshed, retrying...")
                                    // Retry with new token
                                    self.performFetchEvents()
                                } else {
                                    print("❌ [GoogleCalendar] Token refresh failed")
                                    self.errorMessage = "Authentication failed. Please sign in again."
                                }
                            }
                        } else {
                            self.errorMessage = "Authentication expired. Please sign in again."
                        }
                        return
                    }
                    
                    if httpResponse.statusCode != 200 {
                        print("❌ [GoogleCalendar] HTTP Error: \(httpResponse.statusCode)")
                        if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let error = errorData["error"] as? [String: Any],
                           let message = error["message"] as? String {
                            print("   Error message: \(message)")
                            self.errorMessage = "API Error: \(message)"
                        } else {
                            self.errorMessage = "HTTP Error: \(httpResponse.statusCode)"
                        }
                        if let jsonString = String(data: data, encoding: .utf8) {
                            print("   Full response: \(jsonString)")
                        }
                        return
                    }
                }
                
                do {
                    let decoder = JSONDecoder()
                    let response = try decoder.decode(GoogleCalendarResponse.self, from: data)
                    print("✅ [GoogleCalendar] Successfully parsed \(response.items.count) events")
                    
                    for (index, event) in response.items.enumerated() {
                        print("   Event \(index + 1): '\(event.summary)' at \(event.start.startDate?.description ?? "unknown time")")
                    }
                    
                    self.events = response.items
                    self.errorMessage = nil
                } catch {
                    print("❌ [GoogleCalendar] Decoding error: \(error)")
                    self.errorMessage = "Failed to parse events: \(error.localizedDescription)"
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("   Raw response: \(jsonString)")
                    }
                }
            }
        }.resume()
    }
    
    struct CalendarListEntry {
        let id: String?
        let summary: String?
        let primary: Bool?
        
        init?(from dict: [String: Any]) {
            self.id = dict["id"] as? String
            self.summary = dict["summary"] as? String
            self.primary = dict["primary"] as? Bool
        }
    }
    
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

struct GoogleCalendarResponse: Codable {
    let items: [GoogleCalendarEvent]
}

struct CalendarEventCard: View {
    let event: GoogleCalendarEvent
    
    private var timeString: String {
        guard let startDate = event.start.startDate else { return "All Day" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        
        if let endDate = event.end?.startDate {
            return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
        } else {
            return formatter.string(from: startDate)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.summary)
                        .font(.headline)
                        .foregroundColor(dynamicTextColor)
                    
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundColor(dynamicSecondaryTextColor)
                        Text(timeString)
                            .font(.subheadline)
                            .foregroundColor(dynamicSecondaryTextColor)
                    }
                    
                    if let location = event.location {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin.circle")
                                .font(.caption)
                                .foregroundColor(dynamicSecondaryTextColor)
                            Text(location)
                                .font(.caption)
                                .foregroundColor(dynamicSecondaryTextColor)
                                .lineLimit(1)
                        }
                    }
                }
                
                Spacer()
                
                if let htmlLink = event.htmlLink, let url = URL(string: htmlLink) {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                            .foregroundColor(dynamicPrimaryColor)
                    }
                }
            }
            
            if let description = event.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
                    .lineLimit(3)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(dynamicSecondaryBackgroundColor)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
    }
}

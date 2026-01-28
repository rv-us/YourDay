//
//  GoogleCalendarView.swift
//  YourDay
//
//  Google Calendar Integration View - Displays a monthly calendar and timeline view
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
        
        // NOTE: This is accessed a lot (e.g., while building UI). Cache the ISO formatters.
        // ISO8601DateFormatter is safe to reuse; DateFormatter is not guaranteed thread-safe,
        // so we keep the date-only formatter local (date-only events are typically fewer).
        private static let isoWithFractionalSeconds: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()
        
        private static let isoWithoutFractionalSeconds: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f
        }()
        
        var startDate: Date? {
            if let dateTime = dateTime {
                return Self.isoWithFractionalSeconds.date(from: dateTime)
                    ?? Self.isoWithoutFractionalSeconds.date(from: dateTime)
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
    
    /// When `true`, this view is meant to be embedded inside another screen (e.g. `Todoview`)
    /// and should not create its own `NavigationView` or "Done" button.
    let embedded: Bool
    
    @State private var events: [GoogleCalendarEvent] = []
    @State private var monthEvents: [GoogleCalendarEvent] = [] // For calendar dots
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isAuthenticated = false
    @State private var selectedDate = Date()
    @State private var currentMonth = Date()
    @State private var showingMonthPicker = false
    @State private var currentWeekIndex: Int = 0
    
    // Fast lookup cache for “does this day have events?” in the week slider.
    // Store start-of-day Dates so lookups are O(1) instead of scanning all events per cell.
    @State private var monthEventDays: Set<Date> = []
    
    private let weekColumns: [GridItem] = Array(repeating: GridItem(.flexible()), count: 7)
    
    private let calendar = Calendar.current
    private let daysInWeek = ["M", "T", "W", "T", "F", "S", "S"]
    
    // Lightweight formatters (used on main thread for display / query building).
    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()
    
    private static let queryISOFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    
    // Generate weeks for the current month (and surrounding weeks for smooth scrolling)
    private var weeksInRange: [Date] {
        var weeks: [Date] = []
        // Start from 4 weeks before current month to allow backward scrolling
        let startDate = calendar.date(byAdding: .weekOfYear, value: -4, to: currentMonth) ?? currentMonth
        // Get the Monday of that week
        let startWeekMonday = getWeekStart(for: startDate)
        // End 4 weeks after current month
        let endDate = calendar.date(byAdding: .weekOfYear, value: 4, to: currentMonth) ?? currentMonth
        let endWeekMonday = getWeekStart(for: endDate)
        
        var currentWeek = startWeekMonday
        while currentWeek <= endWeekMonday {
            weeks.append(currentWeek)
            if let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: currentWeek) {
                currentWeek = nextWeek
            } else {
                break
            }
        }
        return weeks
    }
    
    // Find the week index that contains the selected date
    private func selectedWeekIndex(in weeks: [Date]) -> Int {
        let selectedWeekStart = getWeekStart(for: selectedDate)
        if let index = weeks.firstIndex(where: { calendar.isDate($0, inSameDayAs: selectedWeekStart) }) {
            return index
        }
        return weeks.count / 2 // Default to middle week
    }
    
    // Generate hourly time slots from 6 AM to 11 PM
    private var timeSlots: [Date] {
        var slots: [Date] = []
        let startHour = 6
        let endHour = 23
        
        for hour in startHour...endHour {
            if let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: selectedDate) {
                slots.append(date)
            }
        }
        return slots
    }
    
    private var todayEvents: [GoogleCalendarEvent] {
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
    
    // MARK: - Week Slider Subviews (helps compiler + improves readability)
    
    private var monthHeader: some View {
        HStack {
            Spacer()
            Button(action: { showingMonthPicker = true }) {
                Text(monthYearString(from: currentMonth))
                    .font(.headline)
                    .foregroundColor(dynamicPrimaryColor)
            }
        }
        .padding(.horizontal)
    }
    
    private var weekdayHeader: some View {
        HStack {
            ForEach(daysInWeek, id: \.self) { day in
                Text(day)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .foregroundColor(dynamicSecondaryTextColor)
            }
        }
        .padding(.horizontal)
    }
    
    private func weekPageView(weekStart: Date, index: Int) -> some View {
        let weekDays = generateWeekDaysFromStart(weekStart)
        return LazyVGrid(columns: weekColumns, spacing: 8) {
            ForEach(weekDays, id: \.self) { date in
                let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                let isToday = calendar.isDateInToday(date)
                let hasEvents = hasEventsOn(date: date)
                
                CalendarDayButton(
                    date: date,
                    isSelected: isSelected,
                    isToday: isToday,
                    hasEvents: hasEvents
                ) {
                    selectedDate = date
                    currentMonth = date
                    fetchEvents()
                }
            }
        }
        .padding(.horizontal)
        .tag(index)
    }
    
    private var weekSlider: some View {
        let weeks = weeksInRange
        return TabView(selection: $currentWeekIndex) {
            ForEach(weeks.indices, id: \.self) { index in
                weekPageView(weekStart: weeks[index], index: index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 80)
        .onChange(of: currentWeekIndex) { _, newValue in
            // Avoid rebuilding the entire week range on every swipe (causes jank).
            // Only “recenter” the range when the user approaches the ends.
            guard newValue < weeks.count else { return }
            let edgeThreshold = 1
            if newValue <= edgeThreshold || newValue >= weeks.count - 1 - edgeThreshold {
                currentMonth = weeks[newValue]
            }
        }
        .onAppear {
            // Set initial week index to the week containing selectedDate
            currentWeekIndex = selectedWeekIndex(in: weeks)
        }
    }
    
    private var calendarContent: some View {
        VStack(spacing: 0) {
            // Week Calendar View with Slider
            VStack(spacing: 12) {
                monthHeader
                weekdayHeader
                weekSlider
            }
            .padding(.vertical, 12)
            .background(dynamicSecondaryBackgroundColor)
            
            Divider()
            
            // Timeline View
            if isLoading {
                Spacer()
                ProgressView("Loading events...")
                    .progressViewStyle(CircularProgressViewStyle(tint: dynamicPrimaryColor))
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
            } else {
                ScrollView {
                    TimelineView(events: todayEvents, selectedDate: selectedDate)
                        .frame(minHeight: UIScreen.main.bounds.height)
                }
            }
        }
        .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
        .sheet(isPresented: $showingMonthPicker) {
            MonthYearPicker(selectedDate: $currentMonth)
                .onChange(of: currentMonth) { _, newDate in
                    showingMonthPicker = false
                    // Switch to the selected date
                    selectedDate = newDate
                    let weeks = weeksInRange
                    currentWeekIndex = selectedWeekIndex(in: weeks)
                    fetchMonthEvents()
                    fetchEvents()
                }
        }
        .onAppear {
            checkAuthentication()
            if isAuthenticated {
                fetchMonthEvents()
                fetchEvents()
            }
        }
        .onChange(of: currentMonth) { _, _ in
            fetchMonthEvents()
        }
        .onChange(of: selectedDate) { _, newDate in
            // Update week index when selectedDate changes programmatically
            let weeks = weeksInRange
            let newWeekIndex = selectedWeekIndex(in: weeks)
            if newWeekIndex != currentWeekIndex && newWeekIndex < weeks.count {
                currentWeekIndex = newWeekIndex
            }
        }
    }
    
    var body: some View {
        Group {
            if embedded {
                calendarContent
            } else {
                NavigationView {
                    calendarContent
                        .navigationTitle("")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
                        .toolbarBackground(.visible, for: .navigationBar)
                        .toolbar {
                            ToolbarItem(placement: .principal) {
                                Text(selectedDate, style: .date)
                                    .fontWeight(.bold)
                                    .foregroundColor(dynamicTextColor)
                            }
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    dismiss()
                                }
                                .foregroundColor(dynamicPrimaryColor)
                            }
                        }
                }
                .navigationViewStyle(.stack)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func monthYearString(from date: Date) -> String {
        Self.monthYearFormatter.string(from: date)
    }
    
    private func getWeekStart(for date: Date) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        let daysFromMonday = (weekday == 1 ? 6 : weekday - 2)
        return calendar.date(byAdding: .day, value: -daysFromMonday, to: date) ?? date
    }
    
    private func generateWeekDaysFromStart(_ weekStart: Date) -> [Date] {
        var weekDays: [Date] = []
        for i in 0..<7 {
            if let day = calendar.date(byAdding: .day, value: i, to: weekStart) {
                weekDays.append(day)
            }
        }
        return weekDays
    }
    
    private func generateWeekDays(for date: Date) -> [Date] {
        let weekStart = getWeekStart(for: date)
        return generateWeekDaysFromStart(weekStart)
    }
    
    private func hasEventsOn(date: Date) -> Bool {
        monthEventDays.contains(calendar.startOfDay(for: date))
    }
    
    private func checkAuthentication() {
        if GIDSignIn.sharedInstance.currentUser != nil {
            isAuthenticated = true
        } else {
            isAuthenticated = false
            errorMessage = "Please sign in with Google to view your calendar"
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
        
        let calendarScope = "https://www.googleapis.com/auth/calendar"
        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController, hint: nil, additionalScopes: [calendarScope]) { [self] signInResult, error in
            if signInResult != nil {
                isAuthenticated = true
                errorMessage = nil
                fetchMonthEvents()
                fetchEvents()
            }
        }
    }
    
    private func fetchEvents() {
        guard let user = GIDSignIn.sharedInstance.currentUser else { return }
        
        isLoading = true
        errorMessage = nil
        
        user.refreshTokensIfNeeded { user, error in
            if let user = user {
                self.performFetchEventsForDate(self.selectedDate, user: user) { fetchedEvents in
                    self.events = fetchedEvents
                    self.isLoading = false
                }
            }
        }
    }
    
    private func fetchMonthEvents() {
        guard let user = GIDSignIn.sharedInstance.currentUser else { return }
        
        // Fetch events for the entire visible week-slider range (not just the calendar month).
        // This keeps the dot indicators correct while avoiding repeated refetches during swipes.
        let weeks = weeksInRange
        let rangeStart = calendar.startOfDay(for: weeks.first ?? currentMonth)
        let rangeEnd = calendar.date(byAdding: .day, value: 7, to: (weeks.last ?? currentMonth))!
        
        user.refreshTokensIfNeeded { user, error in
            if let user = user {
                self.performFetchEventsInRange(start: rangeStart, end: rangeEnd, user: user) { fetchedEvents in
                    self.monthEvents = fetchedEvents
                    
                    // Rebuild fast lookup cache for week slider dots (avoids `.onChange` needing Equatable).
                    var days: Set<Date> = []
                    days.reserveCapacity(fetchedEvents.count)
                    for event in fetchedEvents {
                        if let d = event.start.startDate {
                            days.insert(self.calendar.startOfDay(for: d))
                        }
                    }
                    self.monthEventDays = days
                }
            }
        }
    }
    
    private func performFetchEventsForDate(_ date: Date, user: GIDGoogleUser, completion: @escaping ([GoogleCalendarEvent]) -> Void) {
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        performFetchEventsInRange(start: startOfDay, end: endOfDay, user: user, completion: completion)
    }
    
    private func performFetchEventsInRange(start: Date, end: Date, user: GIDGoogleUser, completion: @escaping ([GoogleCalendarEvent]) -> Void) {
        let accessToken = user.accessToken.tokenString
        
        var urlComponents = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        urlComponents.queryItems = [
            URLQueryItem(name: "timeMin", value: Self.queryISOFormatter.string(from: start)),
            URLQueryItem(name: "timeMax", value: Self.queryISOFormatter.string(from: end)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime")
        ]
        
        var request = URLRequest(url: urlComponents.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let data = data, let result = try? JSONDecoder().decode(GoogleCalendarResponse.self, from: data) {
                DispatchQueue.main.async {
                    completion(result.items)
                }
            } else {
                DispatchQueue.main.async {
                    completion([])
                }
            }
        }.resume()
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

// MARK: - Calendar Day Button

struct CalendarDayButton: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let hasEvents: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 14, weight: isToday ? .bold : .regular))
                    .foregroundColor(isSelected ? .white : (isToday ? dynamicPrimaryColor : dynamicTextColor))
                    .frame(width: 32, height: 32)
                    .background(isSelected ? dynamicPrimaryColor : Color.clear)
                    .clipShape(Circle())
                
                Circle()
                    .fill(hasEvents ? dynamicSecondaryColor : Color.clear)
                    .frame(width: 4, height: 4)
            }
        }
    }
}

// MARK: - Timeline View

struct TimelineView: View {
    let events: [GoogleCalendarEvent]
    let selectedDate: Date
    
    private let calendar = Calendar.current
    private let startHour = 0
    private let endHour = 23
    private let hourHeight: CGFloat = 50 // Reduced from 60 to make it more compact
    
    private var timeSlots: [Date] {
        var slots: [Date] = []
        for hour in startHour...endHour {
            if let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: selectedDate) {
                slots.append(date)
            }
        }
        return slots
    }
    
    // Group events by overlapping time ranges
    private var eventGroups: [[GoogleCalendarEvent]] {
        var groups: [[GoogleCalendarEvent]] = []
        var processed: Set<String> = []
        
        for event in events.sorted(by: { ($0.start.startDate ?? Date()) < ($1.start.startDate ?? Date()) }) {
            if processed.contains(event.id) { continue }
            
            var group: [GoogleCalendarEvent] = [event]
            processed.insert(event.id)
            
            guard let eventStart = event.start.startDate,
                  let eventEnd = event.end?.startDate ?? calendar.date(byAdding: .hour, value: 1, to: eventStart) else {
                continue
            }
            
            // Find all events that overlap with this one
            for otherEvent in events {
                if processed.contains(otherEvent.id) { continue }
                
                guard let otherStart = otherEvent.start.startDate,
                      let otherEnd = otherEvent.end?.startDate ?? calendar.date(byAdding: .hour, value: 1, to: otherStart) else {
                    continue
                }
                
                // Check if events overlap
                if (otherStart < eventEnd && otherEnd > eventStart) {
                    group.append(otherEvent)
                    processed.insert(otherEvent.id)
                }
            }
            
            if !group.isEmpty {
                groups.append(group)
            }
        }
        
        return groups
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Grid background with lines
            VStack(spacing: 0) {
                ForEach(timeSlots, id: \.self) { timeSlot in
                    ZStack(alignment: .topLeading) {
                        // Grid line at the top of each hour
                        Rectangle()
                            .fill(dynamicSecondaryBackgroundColor.opacity(0.3))
                            .frame(height: 1)
                            .padding(.leading, 80)
                        
                        // Time label
                        Text(timeString(from: timeSlot))
                            .font(.caption)
                            .foregroundColor(dynamicSecondaryTextColor)
                            .frame(width: 70, alignment: .trailing)
                            .padding(.trailing, 10)
                    }
                    .frame(height: hourHeight)
                }
            }
            
            // Events overlay - handle overlapping events
            ForEach(Array(eventGroups.enumerated()), id: \.offset) { groupIndex, group in
                ForEach(Array(group.enumerated()), id: \.element.id) { eventIndex, event in
                    if let eventStart = event.start.startDate,
                       let eventEnd = event.end?.startDate ?? calendar.date(byAdding: .hour, value: 1, to: eventStart) {
                        EventBlockView(
                            event: event,
                            eventStart: eventStart,
                            eventEnd: eventEnd,
                            selectedDate: selectedDate,
                            hourHeight: hourHeight,
                            availableWidth: UIScreen.main.bounds.width - 96,
                            groupSize: group.count,
                            groupIndex: eventIndex
                        )
                    }
                }
            }
            
            // Current time indicator
            CurrentTimeIndicator(selectedDate: selectedDate, hourHeight: hourHeight)
        }
        .padding(.horizontal, 0)
        .frame(minHeight: CGFloat(timeSlots.count) * hourHeight)
    }
    
    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Current Time Indicator

struct CurrentTimeIndicator: View {
    let selectedDate: Date
    let hourHeight: CGFloat
    
    private let calendar = Calendar.current
    
    private var currentTimePosition: CGFloat? {
        let now = Date()
        guard calendar.isDate(now, inSameDayAs: selectedDate) else { return nil }
        
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let timeInterval = now.timeIntervalSince(startOfDay)
        let hoursFromStart = timeInterval / 3600.0
        
        // Keep the current-time indicator aligned with the event blocks' vertical offset,
        // but shift it slightly upward for visual alignment.
        return CGFloat(hoursFromStart) * hourHeight + 15
    }
    
    var body: some View {
        if let position = currentTimePosition {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Circle()
                        .fill(dynamicPrimaryColor)
                        .frame(width: 8, height: 8)
                    
                    Rectangle()
                        .fill(dynamicPrimaryColor)
                        .frame(height: 2)
                }
                .offset(x: 70, y: position)
            }
        }
    }
}

struct EventBlockView: View {
    let event: GoogleCalendarEvent
    let eventStart: Date
    let eventEnd: Date
    let selectedDate: Date
    let hourHeight: CGFloat
    let availableWidth: CGFloat
    let groupSize: Int  // Number of overlapping events
    let groupIndex: Int // Index within the overlapping group
    
    private let calendar = Calendar.current
    
    private var topOffset: CGFloat {
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let timeInterval = eventStart.timeIntervalSince(startOfDay)
        let hoursFromStart = timeInterval / 3600.0
        // Calculate exact position: each hour = hourHeight points
        // 8:00 AM = 8 hours = 8 * hourHeight
        // 8:30 AM = 8.5 hours = 8.5 * hourHeight (halfway between 8 and 9)
        // Add 20 points offset to shift all events down
        return CGFloat(hoursFromStart) * hourHeight + 20
    }
    
    private var height: CGFloat {
        let duration = eventEnd.timeIntervalSince(eventStart)
        let hours = duration / 3600.0
        // Height is proportional to duration using the grid's hour height.
        return CGFloat(hours) * hourHeight
    }
    
    // Calculate width and x position for overlapping events
    private var eventWidth: CGFloat {
        // Divide available width by number of overlapping events
        return availableWidth / CGFloat(groupSize)
    }
    
    private var xOffset: CGFloat {
        // Position each event side by side
        return 80 + (CGFloat(groupIndex) * eventWidth)
    }
    
    private var timeRangeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: eventStart)) - \(formatter.string(from: eventEnd))"
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(dynamicPrimaryColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(event.summary)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(timeRangeString)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .frame(width: eventWidth, height: height, alignment: .topLeading)
        .position(x: xOffset + eventWidth / 2, y: topOffset + height / 2)
    }
}


// MARK: - Month Year Picker

struct MonthYearPicker: View {
    @Binding var selectedDate: Date
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            DatePicker("Select Month", selection: $selectedDate, displayedComponents: [.date])
                .datePickerStyle(.graphical)
                .navigationTitle("Select Month")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

// MARK: - Response Models

struct GoogleCalendarResponse: Codable {
    let items: [GoogleCalendarEvent]
}

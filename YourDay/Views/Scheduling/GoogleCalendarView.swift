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

struct GoogleCalendarEvent: Identifiable, Codable, Equatable {
    let id: String
    let summary: String
    let start: EventDateTime
    let end: EventDateTime?
    let description: String?
    let location: String?
    let htmlLink: String?
    /// Populated when merging events from multiple calendars / accounts (not from Google JSON).
    var sourceCalendarId: String?
    /// Stable Google subject / GID `userID` for the account that owns the event.
    var sourceAccountKey: String?
    
    struct EventDateTime: Codable, Equatable {
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

/// Wrapper so we can use sheet(item:) with an optional GoogleCalendarEvent.
private struct IdentifiableCalendarEvent: Identifiable, Equatable {
    let event: GoogleCalendarEvent
    var id: String { event.id }
    static func == (lhs: IdentifiableCalendarEvent, rhs: IdentifiableCalendarEvent) -> Bool {
        lhs.id == rhs.id
    }
}

struct GoogleCalendarView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var firebaseManager: FirebaseManager
    @StateObject private var loginViewModel = LoginViewModel()
    @ObservedObject private var calendarConnectionSettings = CalendarConnectionsSettingsStore.shared
    
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
    @State private var scheduledEventForPopup: IdentifiableCalendarEvent?
    @State private var scheduledTaskPopupDetent: PresentationDetent = .medium
    /// True when user is signed in to Google but has not granted calendar scope (so we show "Grant access").
    @State private var needsCalendarScope = false
    
    /// Timeline zoom: hour row height (pinch to expand/shrink).
    @State private var timelineHourHeight: CGFloat = 50
    @State private var pinchStartHeight: CGFloat = 50

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
        CalendarEventFilter.filterEventsForDay(events, date: selectedDate)
    }
    
    /// Hour we want to center on: current hour today, else 9am.
    private var timelineTargetHour: Int {
        if calendar.isDateInToday(selectedDate) {
            return max(0, min(23, calendar.component(.hour, from: Date())))
        }
        return 9
    }
    
    private func timelineHourRowID(_ hour: Int) -> String { "timeline-hour-\(hour)" }
    
    private func scrollTimelineToAnchor(_ proxy: ScrollViewProxy) {
        let target = timelineHourRowID(timelineTargetHour)
        func jump() {
            proxy.scrollTo(target, anchor: .center)
        }
        jump()
        DispatchQueue.main.async(execute: jump)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: jump)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: jump)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: jump)
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

            if canShowMergedCalendar, needsCalendarScope, GIDSignIn.sharedInstance.currentUser != nil {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .foregroundColor(dynamicSecondaryColor)
                    Text("Grant calendar access to include this Google account. Linked accounts are still shown.")
                        .font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor)
                    Spacer(minLength: 0)
                    Button("Grant") { authenticateWithGoogle() }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(dynamicPrimaryColor)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(dynamicSecondaryBackgroundColor.opacity(0.6))
            }

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
                    
                    if needsCalendarScope {
                        Button(action: authenticateWithGoogle) {
                            HStack {
                                Image(systemName: "calendar.badge.plus")
                                Text("Grant calendar access")
                            }
                            .padding()
                            .background(dynamicPrimaryColor)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    } else if !isAuthenticated {
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
                ScrollViewReader { proxy in
                    ScrollView {
                        ZStack(alignment: .topLeading) {
                            TimelineView(events: todayEvents, selectedDate: selectedDate, hourHeight: timelineHourHeight, onScheduledTaskTap: { scheduledEventForPopup = IdentifiableCalendarEvent(event: $0) })
                                .frame(minHeight: UIScreen.main.bounds.height)
                                .contentShape(Rectangle())
                                .gesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            let newHeight = pinchStartHeight * value
                                            timelineHourHeight = min(90, max(30, newHeight))
                                        }
                                        .onEnded { _ in
                                            pinchStartHeight = timelineHourHeight
                                        }
                                )
                            
                            // Parallel invisible hour column so ScrollViewReader can
                            // target real laid-out positions (TimelineView is a
                            // custom view we don't own, so we mirror its hour rhythm).
                            VStack(spacing: 0) {
                                ForEach(0..<24, id: \.self) { hour in
                                    Color.clear
                                        .frame(height: timelineHourHeight)
                                        .id(timelineHourRowID(hour))
                                }
                            }
                            .allowsHitTesting(false)
                        }
                    }
                    .onAppear {
                        scrollTimelineToAnchor(proxy)
                    }
                    .onChange(of: isLoading) { wasLoading, loading in
                        if wasLoading && !loading && errorMessage == nil {
                            scrollTimelineToAnchor(proxy)
                        }
                    }
                    .onChange(of: selectedDate) { _, _ in
                        scrollTimelineToAnchor(proxy)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 50)
                            .onEnded { value in
                                let horizontalAmount = value.translation.width
                                if abs(horizontalAmount) > 50 {
                                    if horizontalAmount > 0 {
                                        // Swipe right - previous day
                                        if let previousDay = calendar.date(byAdding: .day, value: -1, to: selectedDate) {
                                            selectedDate = previousDay
                                            fetchEvents()
                                        }
                                    } else {
                                        // Swipe left - next day
                                        if let nextDay = calendar.date(byAdding: .day, value: 1, to: selectedDate) {
                                            selectedDate = nextDay
                                            fetchEvents()
                                        }
                                    }
                                }
                            }
                    )
                }
            }
        }
        .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
        .sheet(item: $scheduledEventForPopup) { identifiable in
            ScheduledTaskPopupSheet(
                event: identifiable.event,
                onDismiss: { scheduledEventForPopup = nil },
                onEventDeleted: {
                    fetchEvents()
                    fetchMonthEvents()
                }
            )
            .environmentObject(firebaseManager)
            .presentationDetents([.medium, .large], selection: $scheduledTaskPopupDetent)
            .presentationDragIndicator(.visible)
        }
        .onChange(of: scheduledEventForPopup) { _, newValue in
            if newValue != nil { scheduledTaskPopupDetent = .medium }
        }
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
            if canShowMergedCalendar {
                fetchMonthEvents()
                fetchEvents()
            }
        }
        .onChange(of: currentMonth) { _, _ in
            fetchMonthEvents()
        }
        .onChange(of: selectedDate) { _, newDate in
            // Update currentMonth if selectedDate moves to a different month
            if !calendar.isDate(newDate, equalTo: currentMonth, toGranularity: .month) {
                currentMonth = newDate
            }
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
                    .navigationTitle("Calendar")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Text(selectedDate, style: .date)
                                .fontWeight(.bold)
                                .foregroundColor(dynamicTextColor)
                        }
                    }
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

    /// Primary Google user with full calendar scope, or at least one linked read-only account with a saved refresh token.
    private var canShowMergedCalendar: Bool {
        let calendarScope = "https://www.googleapis.com/auth/calendar"
        if let user = GIDSignIn.sharedInstance.currentUser,
           user.grantedScopes?.contains(calendarScope) == true {
            return true
        }
        return calendarConnectionSettings.linkedReadOnlyAccounts.contains {
            CalendarConnectionKeychain.loadRefreshToken(accountKey: $0.accountKey) != nil
        }
    }

    private func checkAuthentication() {
        GoogleCalendarEventFetchService.syncPrimaryAccountRecordIfNeeded()
        // First, try to restore previous sign-in session
        if GIDSignIn.sharedInstance.currentUser == nil {
            // Ensure configuration is set
            if GIDSignIn.sharedInstance.configuration == nil {
                guard let clientID = FirebaseApp.app()?.options.clientID else {
                    isAuthenticated = false
                    errorMessage = "Google Sign-In not configured"
                    return
                }
                let config = GIDConfiguration(clientID: clientID)
                GIDSignIn.sharedInstance.configuration = config
            }
            
            // Try to restore previous sign-in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                DispatchQueue.main.async {
                    if let user = user {
                        self.isAuthenticated = true
                        let calendarScope = "https://www.googleapis.com/auth/calendar"
                        if user.grantedScopes?.contains(calendarScope) == true {
                            self.needsCalendarScope = false
                            self.errorMessage = nil
                            self.fetchMonthEvents()
                            self.fetchEvents()
                        } else if self.canShowMergedCalendar {
                            self.needsCalendarScope = true
                            self.errorMessage = nil
                            self.fetchMonthEvents()
                            self.fetchEvents()
                        } else {
                            self.needsCalendarScope = true
                            self.errorMessage = "Grant calendar access to see your events and tasks."
                        }
                    } else if self.canShowMergedCalendar {
                        self.isAuthenticated = true
                        self.needsCalendarScope = false
                        self.errorMessage = nil
                        self.fetchMonthEvents()
                        self.fetchEvents()
                    } else {
                        self.isAuthenticated = false
                        self.needsCalendarScope = false
                        self.errorMessage = "Please sign in with Google to view your calendar"
                    }
                }
            }
        } else {
            // User is already signed in
            isAuthenticated = true
            let calendarScope = "https://www.googleapis.com/auth/calendar"
            if GIDSignIn.sharedInstance.currentUser?.grantedScopes?.contains(calendarScope) == true {
                needsCalendarScope = false
                errorMessage = nil
                fetchMonthEvents()
                fetchEvents()
            } else if canShowMergedCalendar {
                needsCalendarScope = true
                errorMessage = nil
                fetchMonthEvents()
                fetchEvents()
            } else {
                needsCalendarScope = true
                errorMessage = "Grant calendar access to see your events and tasks."
            }
        }
    }
    
    private func authenticateWithGoogle() {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            errorMessage = "Google Sign-In not configured"
            return
        }
        
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        // If user is already signed in, just request calendar scope
        if let currentUser = GIDSignIn.sharedInstance.currentUser {
            let calendarScope = "https://www.googleapis.com/auth/calendar"
            if currentUser.grantedScopes?.contains(calendarScope) == true {
                // Already has permission
                isAuthenticated = true
                errorMessage = nil
                fetchMonthEvents()
                fetchEvents()
                return
            }
            
            // Request additional scope
            guard let presentingViewController = getRootViewController() else {
                errorMessage = "Could not present sign-in"
                return
            }
            
            currentUser.addScopes([calendarScope], presenting: presentingViewController) { result, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.errorMessage = "Failed to grant calendar permission: \(error.localizedDescription)"
                        return
                    }
                    
                    if result != nil {
                        self.isAuthenticated = true
                        self.needsCalendarScope = false
                        self.errorMessage = nil
                        self.fetchMonthEvents()
                        self.fetchEvents()
                    }
                }
            }
            return
        }
        
        // User not signed in, perform full sign-in with calendar scope
        guard let presentingViewController = getRootViewController() else {
            errorMessage = "Could not present sign-in"
            return
        }
        
        let calendarScope = "https://www.googleapis.com/auth/calendar"
        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController, hint: nil, additionalScopes: [calendarScope]) { signInResult, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.errorMessage = "Sign-in failed: \(error.localizedDescription)"
                    return
                }
                
                if signInResult != nil {
                    self.isAuthenticated = true
                    self.needsCalendarScope = false
                    self.errorMessage = nil
                    self.fetchMonthEvents()
                    self.fetchEvents()
                }
            }
        }
    }
    
    private func fetchEvents() {
        guard canShowMergedCalendar else { return }

        isLoading = true
        errorMessage = nil

        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        Task { @MainActor in
            do {
                let merged = try await GoogleCalendarEventFetchService.fetchMergedVisibleEvents(
                    start: startOfDay,
                    end: endOfDay
                )
                self.events = merged
                self.isLoading = false
            } catch {
                self.isLoading = false
                self.errorMessage = "Could not load calendar: \(error.localizedDescription)"
            }
        }
    }

    private func fetchMonthEvents() {
        guard canShowMergedCalendar else { return }

        let weeks = weeksInRange
        let rangeStart = calendar.startOfDay(for: weeks.first ?? currentMonth)
        let rangeEnd = calendar.date(byAdding: .day, value: 7, to: (weeks.last ?? currentMonth))!

        Task { @MainActor in
            do {
                let fetchedEvents = try await GoogleCalendarEventFetchService.fetchMergedVisibleEvents(
                    start: rangeStart,
                    end: rangeEnd
                )
                self.monthEvents = fetchedEvents
                var days: Set<Date> = []
                days.reserveCapacity(fetchedEvents.count)
                for event in fetchedEvents {
                    if let d = event.start.startDate {
                        days.insert(self.calendar.startOfDay(for: d))
                    }
                }
                self.monthEventDays = days
            } catch {
                self.errorMessage = "Could not load calendar: \(error.localizedDescription)"
            }
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
    let items: [GoogleCalendarEvent]?
}

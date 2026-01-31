//
//  SchedulingAssistantViewModel.swift
//  YourDay
//
//  ViewModel for AI scheduling assistant
//

import Foundation
import SwiftUI
import FirebaseVertexAI
import FirebaseAuth
import GoogleSignIn

@MainActor
class SchedulingAssistantViewModel: ObservableObject {
    @Published var messages: [SchedulingMessage] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var calendarEvents: [GoogleCalendarEvent] = []
    @Published var schedulePreference: UserSchedulePreference?
    @Published var currentProposal: ProposedSession?
    @Published var showingDeclineReasonInput = false
    @Published var declineReason = ""
    @Published var dayContexts: [String: DayContext] = [:]
    @Published var scheduleNotes: [ScheduleNote] = []
    @Published var recentInteractions: [ProposalInteraction] = []
    @Published var statusMessage: String? // Status message for current agent operation

    private let firebaseManager = FirebaseManager.shared
    private let calendarManager = GoogleCalendarManager.shared

    private var conversationContext: String = ""
    private var declineReasons: [String] = [] // Store reasons for declined proposals
    
    // MARK: - Status Message Helpers
    
    func showStatus(_ message: String) {
        statusMessage = message
    }
    
    func clearStatus() {
        statusMessage = nil
    }
    
    func initialize(userId: String, loadHistory: Bool = true) {
        fetchSchedulePreference()
        fetchDayContexts()
        fetchRecentInteractions()
        if loadHistory {
            fetchSchedulingHistory()
        }
        fetchCalendarEvents()
    }
    
    func resetChat() {
        messages.removeAll()
        conversationContext = ""
        currentProposal = nil
        showingDeclineReasonInput = false
        declineReason = ""
        declineReasons.removeAll()
    }
    
    // MARK: - Calendar Integration
    
    private var calendarFetchCompletion: (() -> Void)?
    private var isFetchingCalendar = false
    
    func ensureCalendarFetched(for date: Date, completion: @escaping () -> Void) {
        // If already fetching, wait for it
        if isFetchingCalendar {
            calendarFetchCompletion = completion
            return
        }
        
        // If calendar is already fetched for this date, call completion immediately
        // Otherwise fetch and then call completion
        fetchCalendarEvents(for: date)
        
        // Wait a moment for the fetch to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            completion()
        }
    }
    
    func fetchCalendarEvents(for date: Date = Date()) {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            calendarFetchCompletion?()
            calendarFetchCompletion = nil
            isFetchingCalendar = false
            return
        }
        
        let accessToken = user.accessToken.tokenString
        guard !accessToken.isEmpty else {
            calendarFetchCompletion?()
            calendarFetchCompletion = nil
            isFetchingCalendar = false
            return
        }
        
        isFetchingCalendar = true
        showStatus("Fetching calendar events...")
        
        // Fetch events for the specified date
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timeMin = formatter.string(from: startOfDay)
        let timeMax = formatter.string(from: endOfDay)
        
        var urlComponents = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        urlComponents.queryItems = [
            URLQueryItem(name: "timeMin", value: timeMin),
            URLQueryItem(name: "timeMax", value: timeMax),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime")
        ]
        
        guard let url = urlComponents.url else {
            calendarFetchCompletion?()
            calendarFetchCompletion = nil
            isFetchingCalendar = false
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "GET"
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            defer {
                DispatchQueue.main.async {
                    self.isFetchingCalendar = false
                    self.calendarFetchCompletion?()
                    self.calendarFetchCompletion = nil
                }
            }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.clearStatus()
                }
                print("Error fetching calendar events: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else { return }
            
            do {
                let response = try JSONDecoder().decode(GoogleCalendarResponse.self, from: data)
                DispatchQueue.main.async {
                    self.calendarEvents = response.items
                    self.clearStatus()
                    print("📅 Fetched \(response.items.count) calendar events for date")
                }
            } catch {
                DispatchQueue.main.async {
                    self.clearStatus()
                }
                print("Error decoding calendar events: \(error.localizedDescription)")
            }
        }.resume()
    }
    
    // MARK: - Schedule Preferences
    
    func fetchSchedulePreference() {
        firebaseManager.fetchSchedulePreference { [weak self] preference, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let preference = preference {
                    self.schedulePreference = preference
                } else if let userId = Auth.auth().currentUser?.uid {
                    // Create default preference
                    self.schedulePreference = UserSchedulePreference(userId: userId)
                }
            }
        }
    }
    
    func updateSchedulePreference(_ updates: [String: Any]) {
        guard Auth.auth().currentUser?.uid != nil else { return }

        firebaseManager.updateSchedulePreference(updates) { [weak self] error in
            if let error = error {
                print("Error updating schedule preference: \(error.localizedDescription)")
                return
            }

            // Refresh preference
            self?.fetchSchedulePreference()
        }
    }

    // MARK: - Day Contexts

    func fetchDayContexts() {
        firebaseManager.fetchDayContexts { [weak self] contexts, error in
            guard let self = self else { return }

            DispatchQueue.main.async {
                if let contexts = contexts {
                    self.dayContexts = contexts
                }
            }
        }
    }

    func saveDayContext(_ context: DayContext) {
        firebaseManager.saveDayContext(context) { [weak self] error in
            if let error = error {
                print("Error saving day context: \(error.localizedDescription)")
                return
            }
            self?.fetchDayContexts()
        }
    }

    // MARK: - Schedule Notes

    func fetchScheduleNotes(for date: Date) {
        firebaseManager.fetchScheduleNotes(for: date) { [weak self] notes, error in
            guard let self = self else { return }

            DispatchQueue.main.async {
                if let notes = notes {
                    self.scheduleNotes = notes
                }
            }
        }
    }

    func saveScheduleNote(_ note: ScheduleNote) {
        firebaseManager.saveScheduleNote(note) { [weak self] error, _ in
            if let error = error {
                print("Error saving schedule note: \(error.localizedDescription)")
                return
            }
            // Refresh notes for the note's date
            self?.fetchScheduleNotes(for: note.date)
        }
    }

    // MARK: - Proposal Interactions

    func fetchRecentInteractions() {
        firebaseManager.fetchRecentInteractions(limit: 20) { [weak self] interactions, error in
            guard let self = self else { return }

            DispatchQueue.main.async {
                if let interactions = interactions {
                    self.recentInteractions = interactions
                }
            }
        }
    }

    func recordInteraction(_ interaction: ProposalInteraction) {
        firebaseManager.saveProposalInteraction(interaction) { [weak self] error in
            if let error = error {
                print("Error saving proposal interaction: \(error.localizedDescription)")
                return
            }
            self?.fetchRecentInteractions()
            self?.updateAcceptanceStatsFromInteraction(interaction)
        }
    }

    private func updateAcceptanceStatsFromInteraction(_ interaction: ProposalInteraction) {
        var stats = schedulePreference?.acceptanceStats ?? AcceptanceStats()

        switch interaction.action {
        case .accepted:
            stats.totalAccepted += 1
            // Track preferred hour from accepted proposal
            if let hour = extractHourFromTimeString(interaction.proposedTime) {
                stats.preferredHours[hour, default: 0] += 1
            }
            stats.preferredDurations[interaction.proposedDuration, default: 0] += 1
        case .acceptedWithChanges:
            stats.totalModified += 1
            // Track modified time/duration as preferred
            if let modifiedTime = interaction.modifiedTime, let hour = extractHourFromTimeString(modifiedTime) {
                stats.preferredHours[hour, default: 0] += 1
            }
            if let modifiedDuration = interaction.modifiedDuration {
                stats.preferredDurations[modifiedDuration, default: 0] += 1
            }
        case .declined:
            stats.totalDeclined += 1
        case .skipped:
            stats.totalSkipped += 1
        }

        // Calculate average accepted duration
        let acceptedDurations = recentInteractions.filter { $0.action == .accepted || $0.action == .acceptedWithChanges }
        if !acceptedDurations.isEmpty {
            let totalDuration = acceptedDurations.reduce(0) { sum, interaction in
                sum + (interaction.modifiedDuration ?? interaction.proposedDuration)
            }
            stats.averageAcceptedDuration = totalDuration / acceptedDurations.count
        }

        firebaseManager.updateAcceptanceStats(stats) { error in
            if let error = error {
                print("Error updating acceptance stats: \(error.localizedDescription)")
            }
        }
    }

    private func extractHourFromTimeString(_ timeStr: String) -> Int? {
        // Parse time strings like "2:00 PM" or "14:00"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        // Try "h:mm a" format first
        formatter.dateFormat = "h:mm a"
        if let date = formatter.date(from: timeStr.trimmingCharacters(in: .whitespaces)) {
            return Calendar.current.component(.hour, from: date)
        }

        // Try "HH:mm" format
        formatter.dateFormat = "HH:mm"
        if let date = formatter.date(from: timeStr.trimmingCharacters(in: .whitespaces)) {
            return Calendar.current.component(.hour, from: date)
        }

        // Try to extract from range like "2:00 PM - 3:30 PM"
        let components = timeStr.components(separatedBy: " - ")
        if let firstTime = components.first {
            formatter.dateFormat = "h:mm a"
            if let date = formatter.date(from: firstTime.trimmingCharacters(in: .whitespaces)) {
                return Calendar.current.component(.hour, from: date)
            }
        }

        return nil
    }
    
    // MARK: - Chat History
    
    func fetchSchedulingHistory() {
        firebaseManager.fetchSchedulingHistory { [weak self] messages, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let messages = messages {
                    self.messages = messages
                    // Build conversation context
                    self.conversationContext = messages.map { "\($0.role.rawValue): \($0.content)" }.joined(separator: "\n")
                }
            }
        }
    }
    
    // MARK: - Calendar Time Slots
    
    var selectedDate: Date = Date()
    
    func formatCalendarAsTimeSlots(for date: Date) -> String {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        // Get day-specific context
        let dayOfWeek = getDayOfWeekString(from: date)
        let dayContext = dayContexts[dayOfWeek]

        // Sort events by start time
        let sortedEvents = calendarEvents.sorted { event1, event2 in
            guard let date1 = event1.start.startDate, let date2 = event2.start.startDate else { return false }
            return date1 < date2
        }

        var timeSlots: [String] = []
        var currentTime = startOfDay

        // Add wake time if set (day-specific overrides global)
        let effectiveWakeTime = dayContext?.wakeTime ?? schedulePreference?.preferredWakeTime
        if let wakeTimeStr = effectiveWakeTime,
           let wakeTime = parseTimeString(wakeTimeStr) {
            let wakeDate = calendar.date(bySettingHour: wakeTime.hour, minute: wakeTime.minute, second: 0, of: date) ?? startOfDay
            if wakeDate > currentTime {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                timeSlots.append("\(formatter.string(from: currentTime)) to \(formatter.string(from: wakeDate)): nothing (before wake time)")
                currentTime = wakeDate
            }
        }

        // Add blocked blocks from day context
        if let blockedBlocks = dayContext?.blockedBlocks {
            for block in blockedBlocks {
                if let blockStart = parseTimeString(block.startTime),
                   let blockEnd = parseTimeString(block.endTime) {
                    let blockStartDate = calendar.date(bySettingHour: blockStart.hour, minute: blockStart.minute, second: 0, of: date) ?? date
                    let blockEndDate = calendar.date(bySettingHour: blockEnd.hour, minute: blockEnd.minute, second: 0, of: date) ?? date
                    let formatter = DateFormatter()
                    formatter.timeStyle = .short
                    let label = block.label ?? "blocked"
                    timeSlots.append("\(formatter.string(from: blockStartDate)) to \(formatter.string(from: blockEndDate)): \(label) (blocked)")
                }
            }
        }

        // Process events
        for event in sortedEvents {
            guard let eventStart = event.start.startDate, eventStart >= startOfDay && eventStart < endOfDay else { continue }

            // Add free time before event
            if eventStart > currentTime {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                timeSlots.append("\(formatter.string(from: currentTime)) to \(formatter.string(from: eventStart)): nothing")
            }

            // Add event
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            if let eventEnd = event.end?.startDate {
                timeSlots.append("\(formatter.string(from: eventStart)) to \(formatter.string(from: eventEnd)): \(event.summary)")
                currentTime = eventEnd
            } else {
                timeSlots.append("\(formatter.string(from: eventStart)): \(event.summary) (all day)")
                currentTime = eventStart
            }
        }

        // Add lunch time if set (day-specific overrides global)
        let effectiveLunchTime = dayContext?.lunchTime ?? schedulePreference?.lunchTime
        if let lunchTimeStr = effectiveLunchTime,
           let lunchTime = parseTimeString(lunchTimeStr) {
            let lunchDate = calendar.date(bySettingHour: lunchTime.hour, minute: lunchTime.minute, second: 0, of: date) ?? date
            if lunchDate > currentTime && lunchDate < endOfDay {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                // Assume 30 min lunch
                let lunchEnd = calendar.date(byAdding: .minute, value: 30, to: lunchDate) ?? lunchDate
                timeSlots.append("\(formatter.string(from: lunchDate)) to \(formatter.string(from: lunchEnd)): lunch")
                currentTime = lunchEnd
            }
        }

        // Add schedule notes for this date
        for note in scheduleNotes {
            if note.isBlocking, let timeRange = note.timeRange {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                timeSlots.append("\(timeRange): \(note.note) (user note - blocked)")
            }
        }

        // Add remaining free time
        if currentTime < endOfDay {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            timeSlots.append("\(formatter.string(from: currentTime)) to \(formatter.string(from: endOfDay)): nothing")
        }

        return timeSlots.joined(separator: "\n")
    }

    private func getDayOfWeekString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date).lowercased()
    }
    
    private func parseTimeString(_ timeStr: String) -> (hour: Int, minute: Int)? {
        let components = timeStr.split(separator: ":")
        guard components.count == 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]) else {
            return nil
        }
        return (hour, minute)
    }
    
    private func formatScheduleConstraints() -> String {
        guard let constraints = schedulePreference?.scheduleConstraints, !constraints.isEmpty else {
            return "None"
        }
        
        return constraints.map { constraint in
            var text = "- \(constraint.reason)"
            if let timeRange = constraint.timeRange {
                text += " (Time: \(timeRange))"
            }
            if let context = constraint.context {
                text += " - \(context)"
            }
            return text
        }.joined(separator: "\n")
    }
    
    // MARK: - AI Integration

    func proposeWorkingSession(backlogItems: [UnifiedBacklogItem], for date: Date = Date(), completion: @escaping (Error?) -> Void) {
        guard Auth.auth().currentUser?.uid != nil else {
            completion(NSError(domain: "SchedulingAssistantViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }

        selectedDate = date
        isLoading = true
        errorMessage = nil

        // Fetch schedule notes for this date
        fetchScheduleNotes(for: date)

        // Always refresh calendar events before proposing to get the latest schedule
        fetchCalendarEvents(for: date)

        // Wait a moment for calendar events to be fetched, then proceed
        // Use a completion-based approach to ensure calendar is fetched
        self.ensureCalendarFetched(for: date) {
            // Show status message for analyzing
            self.showStatus("Analyzing your schedule and backlog...")
            
            // Update status after a brief moment
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showStatus("Finding the best time slot...")
            }
            // Build context for AI with fresh calendar data
            let backlogText = self.formatBacklogItemsWithMetadata(backlogItems)
            let timeSlots = self.formatCalendarAsTimeSlots(for: date)
            let recurringCommitmentsText = self.schedulePreference?.recurringCommitments.map { commitment in
                "- \(commitment.eventName): \(commitment.daysOfWeek.joined(separator: ", ")) at \(commitment.time)"
            }.joined(separator: "\n") ?? "None"

            let declineReasonsText = self.declineReasons.isEmpty ? "None" : self.declineReasons.joined(separator: "; ")

            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .full
            let dateString = dateFormatter.string(from: date)

            // Get day-specific context
            let dayOfWeek = self.getDayOfWeekString(from: date)
            let dayContext = self.dayContexts[dayOfWeek]
            let dayContextText = self.formatDayContext(dayContext, dayOfWeek: dayOfWeek)

            // Get schedule notes for this date
            let scheduleNotesText = self.formatScheduleNotes()

            // Get recent interactions for learning
            let interactionHistoryText = self.formatRecentInteractions(for: dayOfWeek)

            // Get acceptance stats
            let acceptanceStatsText = self.formatAcceptanceStats()

            // Get current time for context
            let now = Date()
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .medium
            timeFormatter.dateStyle = .none
            let currentTimeString = timeFormatter.string(from: now)

            // Check if the selected date is today
            let calendar = Calendar.current
            let isToday = calendar.isDate(date, inSameDayAs: now)
            let currentTimeContext: String
            if isToday {
                currentTimeContext = """
                CURRENT TIME: \(currentTimeString) on \(dateString)
                CRITICAL: You MUST NOT propose any working session that starts before the current time (\(currentTimeString)). Only propose times in the future.
                """
            } else if date > now {
                // Future date
                currentTimeContext = """
                CURRENT TIME: \(currentTimeString)
                TARGET DATE: \(dateString) (future date)
                """
            } else {
                // Past date (shouldn't happen, but handle it)
                currentTimeContext = """
                CURRENT TIME: \(currentTimeString)
                WARNING: The target date (\(dateString)) is in the past. Only propose times if absolutely necessary.
                """
            }

            let prompt = """
            You are a scheduling assistant. Based on the user's backlog items and their calendar for \(dateString) (\(dayOfWeek.capitalized)), propose a working session.

            \(currentTimeContext)

            IMPORTANT: The calendar below shows the CURRENT state including any events that were just created. Make sure your proposed time does NOT conflict with any existing events.

            User's Backlog Items (with priority and estimated duration):
            \(backlogText.isEmpty ? "None" : backlogText)

            Calendar Time Slots for \(dateString) (CURRENT - includes all scheduled events):
            \(timeSlots)

            Day-Specific Context for \(dayOfWeek.capitalized):
            \(dayContextText)

            Schedule Notes for This Date:
            \(scheduleNotesText)

            User's Schedule Preferences:
            - Preferred wake time: \(self.schedulePreference?.preferredWakeTime ?? "Not set")
            - Lunch time: \(self.schedulePreference?.lunchTime ?? "Not set")
            - Recurring commitments: \(recurringCommitmentsText)

            Learned Schedule Constraints (reasons why user can't work even when calendar is free):
            \(self.formatScheduleConstraints())

            Previous Decline Reasons (learn from these):
            \(declineReasonsText)

            User's Interaction History (what they've accepted/declined before on \(dayOfWeek.capitalized)):
            \(interactionHistoryText)

            User's Preference Statistics:
            \(acceptanceStatsText)

            Instructions:
            1. Analyze the backlog items and identify tasks that can be grouped together into one working session:
               - BATCH quick tasks (<15 min each) together into one session
               - GROUP tasks by category when they're related
               - Keep SINGLE focus tasks that need dedicated attention separate
            2. Consider task priorities (higher number = higher priority) and estimated durations
            3. Find an available time slot that fits the user's schedule - CHECK THE CALENDAR CAREFULLY to avoid conflicts
            4. Consider their wake time, lunch time, day-specific context, schedule notes, and any decline reasons
            5. LEARN from their interaction history - propose times and durations similar to what they've accepted before
            6. \(isToday ? "CRITICAL: The proposed time MUST be after the current time (\(currentTimeString)). Do NOT propose any time in the past." : "Propose a time that works for the target date.")
            7. IMPORTANT: If the user has indicated they don't want to do tasks today (e.g., in previous decline reasons mentioning "not today", "skip today"), DO NOT propose those tasks. Instead, only propose tasks they haven't declined for today.
            8. Return ONLY a JSON object with this exact format:
            {
                "tasks": ["Task 1", "Task 2", "Task 3"] or ["Single Task"],
                "taskDetails": [{"title": "Task 1", "estimatedDuration": 15, "priority": 5}],
                "workingSessionTime": "2:00 PM - 3:30 PM",
                "groupingType": "quickTaskBatch" or "relatedTasks" or "singleFocus",
                "reason": "Brief reason why this time works and why these tasks are grouped together"
            }

            Do NOT include any other text, only the JSON.
            """

            Task {
                do {
                    DispatchQueue.main.async {
                        self.showStatus("Proposing working session...")
                    }
                    
                    let vertex = VertexAI.vertexAI()
                    let model = vertex.generativeModel(modelName: "gemini-2.5-flash")

                    let userMessage = ModelContent(role: "user", parts: [TextPart(prompt)])
                    let response = try await model.generateContent([userMessage])

                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.clearStatus()

                        guard let text = response.text else {
                            self.errorMessage = "AI returned no text"
                            completion(NSError(domain: "SchedulingAssistantViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "AI returned no text"]))
                            return
                        }

                        // Parse JSON response
                        if let proposal = self.parseProposal(from: text, backlogItems: backlogItems) {
                            self.currentProposal = proposal
                            completion(nil)
                        } else {
                            self.errorMessage = "Failed to parse proposal. Response: \(text)"
                            completion(NSError(domain: "SchedulingAssistantViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse proposal"]))
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.clearStatus()
                        self.errorMessage = "Failed to generate response: \(error.localizedDescription)"
                        completion(error)
                    }
                }
            }
        }
    }

    // MARK: - Formatting Helpers

    private func formatBacklogItemsWithMetadata(_ items: [UnifiedBacklogItem]) -> String {
        return items.map { item in
            var line = "- \(item.title)"
            if let priority = item.priority, priority > 0 {
                line += " [Priority: \(priority)]"
            }
            if let duration = item.estimatedDuration {
                line += " [Est: \(duration) min]"
            }
            if let category = item.category {
                line += " [Category: \(category)]"
            }
            if !item.description.isEmpty {
                line += " - \(item.description)"
            }
            return line
        }.joined(separator: "\n")
    }

    private func formatDayContext(_ context: DayContext?, dayOfWeek: String) -> String {
        guard let context = context else {
            return "No specific settings for \(dayOfWeek.capitalized)"
        }

        var lines: [String] = []

        if let wakeTime = context.wakeTime {
            lines.append("- Wake time: \(wakeTime)")
        }
        if let lunchTime = context.lunchTime {
            lines.append("- Lunch time: \(lunchTime)")
        }
        if !context.generalActivities.isEmpty {
            lines.append("- Activities: \(context.generalActivities.joined(separator: ", "))")
        }
        if !context.preferredWorkBlocks.isEmpty {
            let blocks = context.preferredWorkBlocks.map { "\($0.startTime)-\($0.endTime)" }.joined(separator: ", ")
            lines.append("- Preferred work times: \(blocks)")
        }
        if !context.blockedBlocks.isEmpty {
            let blocks = context.blockedBlocks.map { block in
                let label = block.label ?? "blocked"
                return "\(block.startTime)-\(block.endTime) (\(label))"
            }.joined(separator: ", ")
            lines.append("- Blocked times: \(blocks)")
        }

        return lines.isEmpty ? "No specific settings for \(dayOfWeek.capitalized)" : lines.joined(separator: "\n")
    }

    private func formatScheduleNotes() -> String {
        guard !scheduleNotes.isEmpty else {
            return "None"
        }

        return scheduleNotes.map { note in
            var line = "- \(note.note)"
            if let timeRange = note.timeRange {
                line += " (\(timeRange))"
            }
            if note.isBlocking {
                line += " [BLOCKING - avoid this time]"
            }
            return line
        }.joined(separator: "\n")
    }

    private func formatRecentInteractions(for dayOfWeek: String) -> String {
        let relevantInteractions = recentInteractions.filter { $0.dayOfWeek.lowercased() == dayOfWeek.lowercased() }

        guard !relevantInteractions.isEmpty else {
            return "No previous interactions on \(dayOfWeek.capitalized)"
        }

        return relevantInteractions.prefix(5).map { interaction in
            var line = "- \(interaction.action.rawValue.capitalized)"
            line += " at \(interaction.proposedTime)"
            line += " (\(interaction.proposedDuration) min)"
            if let modifiedTime = interaction.modifiedTime {
                line += " -> modified to \(modifiedTime)"
            }
            if let modifiedDuration = interaction.modifiedDuration {
                line += " (\(modifiedDuration) min)"
            }
            if let reason = interaction.declineReason {
                line += " - Reason: \(reason)"
            }
            return line
        }.joined(separator: "\n")
    }

    private func formatAcceptanceStats() -> String {
        guard let stats = schedulePreference?.acceptanceStats else {
            return "No statistics yet"
        }

        var lines: [String] = []
        lines.append("- Total accepted: \(stats.totalAccepted), declined: \(stats.totalDeclined), modified: \(stats.totalModified), skipped: \(stats.totalSkipped)")

        if let avgDuration = stats.averageAcceptedDuration {
            lines.append("- Average accepted session duration: \(avgDuration) min")
        }

        // Find top preferred hours
        let sortedHours = stats.preferredHours.sorted { $0.value > $1.value }
        if !sortedHours.isEmpty {
            let topHours = sortedHours.prefix(3).map { hour, count in
                let formatter = DateFormatter()
                formatter.dateFormat = "h a"
                let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
                return formatter.string(from: date)
            }.joined(separator: ", ")
            lines.append("- Preferred hours: \(topHours)")
        }

        return lines.joined(separator: "\n")
    }
    
    func sendMessage(_ content: String, backlogItems: [UnifiedBacklogItem], completion: @escaping (Error?) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "SchedulingAssistantViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        // Save user message
        let userMessage = SchedulingMessage(userId: userId, role: .user, content: content)
        messages.append(userMessage)
        
        firebaseManager.saveSchedulingMessage(userMessage) { error in
            if let error = error {
                print("Error saving user message: \(error.localizedDescription)")
            }
        }
        
        // Update conversation context
        conversationContext += "\nuser: \(content)"
        
        // If this is a decline reason, save it and propose another time
        if showingDeclineReasonInput {
            declineReasons.append(content)
            showingDeclineReasonInput = false
            declineReason = ""
            
            // Save to preferences
            var learnedPatterns = schedulePreference?.learnedPatterns ?? [:]
            learnedPatterns["decline_reason_\(Date().timeIntervalSince1970)"] = content
            updateSchedulePreference(["learnedPatterns": learnedPatterns])
            
            // Clear current proposal before proposing a new one to ensure UI updates properly
            currentProposal = nil
            
            // Propose another time
            proposeWorkingSession(backlogItems: backlogItems, completion: completion)
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // Check for "not today" intent
        if detectNotTodayIntent(content) {
            // If user doesn't want to do tasks today, skip current proposal tasks
            if let proposal = currentProposal {
                let tasksToSkip = proposal.tasks
                skipTask(tasks: tasksToSkip) {
                    // Move to next session
                    if let userId = Auth.auth().currentUser?.uid {
                        let message = SchedulingMessage(
                            userId: userId,
                            role: .assistant,
                            content: "Got it! I'll skip those tasks for today. Let me propose the next session."
                        )
                        self.messages.append(message)
                        self.firebaseManager.saveSchedulingMessage(message) { _ in }
                    }
                    completion(nil)
                }
                return
            } else {
                // No current proposal, but user said "not today" - acknowledge and complete
                if let userId = Auth.auth().currentUser?.uid {
                    let message = SchedulingMessage(
                        userId: userId,
                        role: .assistant,
                        content: "Understood! I'll keep that in mind for today."
                    )
                    self.messages.append(message)
                    self.firebaseManager.saveSchedulingMessage(message) { _ in }
                }
                completion(nil)
                return
            }
        }
        
        showStatus("Thinking...")
        
        // Regular chat message - use simpler prompt
        let prompt = """
        User message: \(content)
        
        Previous conversation:
        \(conversationContext)
        
        Respond helpfully and naturally. If the user is explaining why they can't do something, acknowledge it and learn from it.
        If the user indicates they don't want to do tasks today (e.g., "not today", "skip today"), acknowledge and move on.
        """
        
        Task {
            do {
                let vertex = VertexAI.vertexAI()
                let model = vertex.generativeModel(modelName: "gemini-2.5-flash")
                
                let aiMessage = ModelContent(role: "user", parts: [TextPart(prompt)])
                let response = try await model.generateContent([aiMessage])
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.clearStatus()
                    
                    guard let text = response.text else {
                        self.errorMessage = "AI returned no text"
                        completion(NSError(domain: "SchedulingAssistantViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "AI returned no text"]))
                        return
                    }
                    
                    // Save assistant message
                    let assistantMessage = SchedulingMessage(userId: userId, role: .assistant, content: text)
                    self.messages.append(assistantMessage)
                    self.conversationContext += "\nassistant: \(text)"
                    
                    self.firebaseManager.saveSchedulingMessage(assistantMessage) { error in
                        if let error = error {
                            print("Error saving assistant message: \(error.localizedDescription)")
                        }
                    }
                    
                    // Analyze response for schedule preferences
                    self.analyzeAndUpdatePreferences(userMessage: content, assistantResponse: text)
                    
                    completion(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.clearStatus()
                    self.errorMessage = "Failed to generate response: \(error.localizedDescription)"
                    completion(error)
                }
            }
        }
    }
    
    // MARK: - Proposal Parsing

    private func parseProposal(from text: String, backlogItems: [UnifiedBacklogItem] = []) -> ProposedSession? {
        // Try to extract JSON from the response - handle multiline JSON with nested objects
        let jsonPattern = "\\{(?:[^{}]|\\{[^{}]*\\}|\\[[^\\[\\]]*\\])*\\}"
        if let regex = try? NSRegularExpression(pattern: jsonPattern, options: []),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range, in: text) {
            let jsonString = String(text[range])
            if let data = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let workingSessionTime = json["workingSessionTime"] as? String {

                // Handle both single task and multiple tasks
                var tasks: [String] = []
                if let taskArray = json["tasks"] as? [String] {
                    tasks = taskArray
                } else if let singleTask = json["task"] as? String {
                    // Backward compatibility with single task format
                    tasks = [singleTask]
                } else {
                    return nil
                }

                // Parse time range
                let timeComponents = workingSessionTime.components(separatedBy: " - ")
                let startTime = parseTimeRange(timeComponents.first ?? "")
                let endTime = timeComponents.count > 1 ? parseTimeRange(timeComponents[1]) : nil

                // Parse task details if present
                var taskDetails: [ProposedTaskDetail]? = nil
                if let detailsArray = json["taskDetails"] as? [[String: Any]] {
                    taskDetails = detailsArray.compactMap { detail in
                        guard let title = detail["title"] as? String else { return nil }
                        return ProposedTaskDetail(
                            title: title,
                            estimatedDuration: detail["estimatedDuration"] as? Int,
                            priority: detail["priority"] as? Int ?? 0
                        )
                    }
                } else {
                    // Build task details from backlog items if not provided by AI
                    taskDetails = tasks.compactMap { taskTitle in
                        if let item = backlogItems.first(where: { $0.title == taskTitle }) {
                            return ProposedTaskDetail(
                                title: taskTitle,
                                estimatedDuration: item.estimatedDuration,
                                priority: item.priority ?? 0
                            )
                        }
                        return ProposedTaskDetail(title: taskTitle, estimatedDuration: nil, priority: 0)
                    }
                }

                // Parse grouping type
                var groupingType: TaskGroupingType? = nil
                if let groupingStr = json["groupingType"] as? String {
                    groupingType = TaskGroupingType(rawValue: groupingStr)
                }

                return ProposedSession(
                    tasks: tasks,
                    workingSessionTime: workingSessionTime,
                    startTime: startTime,
                    endTime: endTime,
                    reason: json["reason"] as? String,
                    taskDetails: taskDetails,
                    adjustedStartTime: nil,
                    adjustedDuration: nil,
                    groupingType: groupingType
                )
            }
        }
        return nil
    }
    
    private func parseTimeRange(_ timeStr: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        // Try to parse with selected date
        let calendar = Calendar.current
        let selectedDay = calendar.startOfDay(for: selectedDate)
        
        if let time = formatter.date(from: timeStr.trimmingCharacters(in: .whitespaces)) {
            let components = calendar.dateComponents([.hour, .minute], from: time)
            return calendar.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: 0, of: selectedDay)
        }
        
        return nil
    }
    
    // MARK: - Proposal Actions

    func acceptProposal(backlogItems: [UnifiedBacklogItem], onComplete: @escaping ([String]) -> Void) {
        guard let proposal = currentProposal else { return }

        // Determine if this is an acceptance with modifications
        let hasModifications = proposal.hasModifications
        let effectiveStart = proposal.effectiveStartTime ?? proposal.startTime
        let effectiveEnd = proposal.effectiveEndTime ?? proposal.endTime

        // Create calendar event for the working session
        if let startTime = effectiveStart {
            // Adjust startTime to selected date
            let calendar = Calendar.current
            let selectedDateStart = calendar.startOfDay(for: selectedDate)
            let timeComponents = calendar.dateComponents([.hour, .minute], from: startTime)
            let adjustedStartTime = calendar.date(bySettingHour: timeComponents.hour ?? 0, minute: timeComponents.minute ?? 0, second: 0, of: selectedDateStart) ?? startTime

            let endTime = effectiveEnd ?? Calendar.current.date(byAdding: .hour, value: 1, to: adjustedStartTime) ?? adjustedStartTime
            let adjustedEndTime = calendar.date(bySettingHour: calendar.component(.hour, from: endTime), minute: calendar.component(.minute, from: endTime), second: 0, of: selectedDateStart) ?? endTime

            // Create event title with all tasks
            let tasksTitle = proposal.tasks.count == 1
                ? proposal.tasks.first ?? "Working Session"
                : "Working Session: \(proposal.tasks.count) tasks"
            let tasksDescription = proposal.tasks.joined(separator: "\n• ")
            let fullDescription = "Tasks:\n• \(tasksDescription)\n\n\(proposal.reason ?? "")"

            calendarManager.createCalendarEvent(
                title: tasksTitle,
                start: adjustedStartTime,
                end: adjustedEndTime,
                description: fullDescription
            ) { [weak self] eventId, error in
                guard let self = self else { return }

                if let error = error {
                    print("Error creating calendar event: \(error.localizedDescription)")
                    onComplete(proposal.tasks)
                } else {
                    print("✅ Created working session calendar event")

                    // Record interaction for learning
                    let duration = Int(adjustedEndTime.timeIntervalSince(adjustedStartTime) / 60)
                    let interaction = ProposalInteraction(
                        proposedTasks: proposal.tasks,
                        proposedTime: proposal.workingSessionTime,
                        proposedDuration: proposal.effectiveDuration ?? duration,
                        action: hasModifications ? .acceptedWithChanges : .accepted,
                        modifiedTime: hasModifications ? proposal.effectiveTimeString : nil,
                        modifiedDuration: proposal.adjustedDuration,
                        declineReason: nil,
                        dayOfWeek: self.getDayOfWeekString(from: self.selectedDate)
                    )
                    self.recordInteraction(interaction)

                    self.currentProposal = nil

                    // Refresh calendar events to get the newly created event
                    // Wait a moment for Google Calendar to sync
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.fetchCalendarEvents(for: self.selectedDate)

                        // Wait a bit more for the fetch to complete, then call onComplete
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            // Save acceptance message
                            if let userId = Auth.auth().currentUser?.uid {
                                let tasksList = proposal.tasks.joined(separator: ", ")
                                let timeStr = hasModifications ? proposal.effectiveTimeString : proposal.workingSessionTime
                                let message = SchedulingMessage(
                                    userId: userId,
                                    role: .user,
                                    content: hasModifications
                                        ? "Accepted with changes: \(tasksList) at \(timeStr)"
                                        : "Accepted: \(tasksList) at \(timeStr)"
                                )
                                self.messages.append(message)
                                self.firebaseManager.saveSchedulingMessage(message) { _ in }
                            }

                            onComplete(proposal.tasks)
                        }
                    }
                }
            }
        } else {
            // No valid time, just clear
            currentProposal = nil
            onComplete(proposal.tasks)
        }
    }

    func declineProposal(reason: String? = nil) {
        guard let proposal = currentProposal else { return }

        // Record interaction for learning
        let duration = proposal.effectiveDuration ?? 60
        let interaction = ProposalInteraction(
            proposedTasks: proposal.tasks,
            proposedTime: proposal.workingSessionTime,
            proposedDuration: duration,
            action: .declined,
            modifiedTime: nil,
            modifiedDuration: nil,
            declineReason: reason,
            dayOfWeek: getDayOfWeekString(from: selectedDate)
        )
        recordInteraction(interaction)

        showingDeclineReasonInput = true
    }

    func skipTask(tasks: [String], onComplete: @escaping () -> Void) {
        guard let proposal = currentProposal else {
            onComplete()
            return
        }

        // Record interaction for learning
        let duration = proposal.effectiveDuration ?? 60
        let interaction = ProposalInteraction(
            proposedTasks: tasks,
            proposedTime: proposal.workingSessionTime,
            proposedDuration: duration,
            action: .skipped,
            modifiedTime: nil,
            modifiedDuration: nil,
            declineReason: nil,
            dayOfWeek: getDayOfWeekString(from: selectedDate)
        )
        recordInteraction(interaction)

        // Save skip message
        if let userId = Auth.auth().currentUser?.uid {
            let tasksList = tasks.joined(separator: ", ")
            let message = SchedulingMessage(
                userId: userId,
                role: .user,
                content: "Skipped: \(tasksList)"
            )
            messages.append(message)
            firebaseManager.saveSchedulingMessage(message) { _ in }
        }

        currentProposal = nil
        onComplete()
    }
    
    // MARK: - Not Today Detection
    
    private func detectNotTodayIntent(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        let notTodayPhrases = [
            "not today",
            "skip today",
            "don't want to do it today",
            "don't want to today",
            "not doing it today",
            "skip it today",
            "not today please",
            "maybe tomorrow",
            "not right now",
            "later",
            "not now"
        ]
        
        return notTodayPhrases.contains { lowercased.contains($0) }
    }
    
    // MARK: - Preference Learning

    private func analyzeAndUpdatePreferences(userMessage: String, assistantResponse: String) {
        // Use AI to extract any schedule constraints, preferences, or one-off notes from user message
        let analysisPrompt = """
        Analyze the following user message for scheduling information.
        The user's calendar might show the time as free, but they have personal preferences or constraints.

        User message: "\(userMessage)"

        Extract ANY of the following:
        1. Schedule constraints (recurring patterns):
           - Time-specific constraints (e.g., "I'm eating lunch", "I normally get up at 9 am", "I have gym at 6 pm")
           - General preferences (e.g., "I don't work after 8 pm", "I prefer mornings")
           - Recurring commitments that aren't on their calendar (e.g., "I have class every Monday")

        2. One-off schedule notes (specific date events mentioned):
           - Meeting with someone on a specific date/day (e.g., "I have lunch with Sarah Tuesday at 2pm")
           - Appointments on specific days (e.g., "dentist appointment Friday morning")
           - Any specific date commitment that should block scheduling

        Respond in JSON format:
        {
            "scheduleConstraints": [
                {
                    "reason": "Brief description",
                    "timeRange": "Time range if specific (e.g., '12:00-13:00') or null",
                    "context": "Additional context if needed or null"
                }
            ],
            "recurringCommitment": {
                "eventName": "Class",
                "daysOfWeek": ["MO", "WE"],
                "time": "10:00",
                "frequency": "WEEKLY"
            } or null,
            "scheduleNote": {
                "note": "lunch with Sarah",
                "dayOfWeek": "tuesday",
                "timeRange": "14:00-15:00",
                "isBlocking": true
            } or null
        }

        If no constraints or notes found, return empty arrays and null values.
        """
        
        Task {
            do {
                let vertex = VertexAI.vertexAI()
                let model = vertex.generativeModel(modelName: "gemini-2.5-flash")
                
                let analysisMessage = ModelContent(role: "user", parts: [TextPart(analysisPrompt)])
                let response = try await model.generateContent([analysisMessage])
                
                guard let text = response.text else { return }
                
                // Parse JSON response
                if let data = text.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    
                    let updates: [String: Any] = [:]
                    var constraintsToAdd: [ScheduleConstraint] = []
                    
                    // Extract schedule constraints
                    if let constraintsArray = json["scheduleConstraints"] as? [[String: Any]] {
                        for constraintDict in constraintsArray {
                            if let reason = constraintDict["reason"] as? String {
                                let constraint = ScheduleConstraint(
                                    reason: reason,
                                    timeRange: constraintDict["timeRange"] as? String,
                                    context: constraintDict["context"] as? String
                                )
                                constraintsToAdd.append(constraint)
                            }
                        }
                    }
                    
                    // Handle recurring commitment
                    var commitmentToAdd: RecurringCommitment? = nil
                    if let recurringDict = json["recurringCommitment"] as? [String: Any],
                       let eventName = recurringDict["eventName"] as? String,
                       let daysOfWeek = recurringDict["daysOfWeek"] as? [String],
                       let time = recurringDict["time"] as? String,
                       let frequency = recurringDict["frequency"] as? String {
                        
                        commitmentToAdd = RecurringCommitment(
                            eventName: eventName,
                            daysOfWeek: daysOfWeek,
                            time: time,
                            frequency: frequency
                        )
                        
                        // Check if we should create calendar event (if assistant suggested it)
                        if assistantResponse.lowercased().contains("create") && assistantResponse.lowercased().contains("calendar") {
                            createRecurringCalendarEvent(eventName: eventName, daysOfWeek: daysOfWeek, time: time)
                        }
                    }
                    
                    // Handle schedule note extraction (one-off events from chat)
                    if let noteDict = json["scheduleNote"] as? [String: Any],
                       let noteText = noteDict["note"] as? String,
                       let dayOfWeekStr = noteDict["dayOfWeek"] as? String {

                        // Calculate the date for the mentioned day of week
                        let noteDate = self.getNextDateForDayOfWeek(dayOfWeekStr)
                        let timeRange = noteDict["timeRange"] as? String
                        let isBlocking = noteDict["isBlocking"] as? Bool ?? true

                        let scheduleNote = ScheduleNote(
                            date: noteDate,
                            note: noteText,
                            timeRange: timeRange,
                            isBlocking: isBlocking
                        )

                        // Save the schedule note
                        self.firebaseManager.saveScheduleNote(scheduleNote) { error, noteId in
                            if let error = error {
                                print("Error saving schedule note: \(error.localizedDescription)")
                            } else {
                                print("✅ Saved schedule note: \(noteText)")
                                // Refresh notes
                                self.fetchScheduleNotes(for: noteDate)

                                // Send confirmation message to user
                                if let userId = Auth.auth().currentUser?.uid {
                                    let confirmationMessage = SchedulingMessage(
                                        userId: userId,
                                        role: .assistant,
                                        content: "Got it! I'll avoid scheduling during your \(noteText) on \(dayOfWeekStr.capitalized)\(timeRange != nil ? " at \(timeRange!)" : "")."
                                    )
                                    DispatchQueue.main.async {
                                        self.messages.append(confirmationMessage)
                                    }
                                    self.firebaseManager.saveSchedulingMessage(confirmationMessage) { _ in }
                                }
                            }
                        }
                    }

                    // Update preferences with new constraints
                    if !constraintsToAdd.isEmpty || commitmentToAdd != nil {
                        firebaseManager.fetchSchedulePreference { [weak self] preference, _ in
                            guard let self = self, let pref = preference else { return }

                            var constraints = pref.scheduleConstraints
                            constraints.append(contentsOf: constraintsToAdd)

                            var commitments = pref.recurringCommitments
                            if let commitment = commitmentToAdd {
                                commitments.append(commitment)
                            }

                            // Build update dictionary
                            var prefDict: [String: Any] = [
                                "scheduleConstraints": constraints.map { constraint in
                                    var constraintDict: [String: Any] = [
                                        "reason": constraint.reason
                                    ]
                                    if let timeRange = constraint.timeRange {
                                        constraintDict["timeRange"] = timeRange
                                    }
                                    if let context = constraint.context {
                                        constraintDict["context"] = context
                                    }
                                    return constraintDict
                                },
                                "recurringCommitments": commitments.map { commitment in
                                    [
                                        "eventName": commitment.eventName,
                                        "daysOfWeek": commitment.daysOfWeek,
                                        "time": commitment.time,
                                        "frequency": commitment.frequency
                                    ]
                                }
                            ]

                            if !updates.isEmpty {
                                prefDict.merge(updates) { _, new in new }
                            }

                            self.updateSchedulePreference(prefDict)
                        }
                    } else if !updates.isEmpty {
                        // Update preferences without constraints or commitments
                        updateSchedulePreference(updates)
                    }
                }
            } catch {
                print("Error analyzing preferences: \(error.localizedDescription)")
            }
        }
    }

    private func getNextDateForDayOfWeek(_ dayOfWeekStr: String) -> Date {
        let calendar = Calendar.current
        let today = Date()

        let dayMapping: [String: Int] = [
            "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
            "thursday": 5, "friday": 6, "saturday": 7
        ]

        guard let targetWeekday = dayMapping[dayOfWeekStr.lowercased()] else {
            return today
        }

        let currentWeekday = calendar.component(.weekday, from: today)
        var daysToAdd = targetWeekday - currentWeekday

        if daysToAdd <= 0 {
            daysToAdd += 7
        }

        return calendar.date(byAdding: .day, value: daysToAdd, to: today) ?? today
    }
    
    // MARK: - Calendar Event Creation
    
    func createRecurringCalendarEvent(eventName: String, daysOfWeek: [String], time: String) {
        // Parse time string (e.g., "10:00")
        let components = time.split(separator: ":")
        guard components.count == 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]) else {
            return
        }
        
        // Create start time (next occurrence of the specified day and time)
        let calendar = Calendar.current
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: Date())
        dateComponents.hour = hour
        dateComponents.minute = minute
        
        // Find next occurrence
        var startTime = calendar.date(from: dateComponents) ?? Date()
        if startTime < Date() {
            startTime = calendar.date(byAdding: .day, value: 1, to: startTime) ?? Date()
        }
        
        // Convert day names to RRULE format if needed
        let rruleDays = daysOfWeek.map { day in
            switch day.uppercased() {
            case "MONDAY", "MON", "MO": return "MO"
            case "TUESDAY", "TUE", "TU": return "TU"
            case "WEDNESDAY", "WED", "WE": return "WE"
            case "THURSDAY", "THU", "TH": return "TH"
            case "FRIDAY", "FRI", "FR": return "FR"
            case "SATURDAY", "SAT", "SA": return "SA"
            case "SUNDAY", "SUN", "SU": return "SU"
            default: return day.uppercased()
            }
        }
        
        calendarManager.createRecurringEvent(
            title: eventName,
            startTime: startTime,
            daysOfWeek: rruleDays
        ) { [weak self] eventId, error in
            if let error = error {
                print("Error creating recurring calendar event: \(error.localizedDescription)")
            } else if let eventId = eventId {
                print("✅ Created recurring calendar event: \(eventId)")
                // Refresh calendar events
                self?.fetchCalendarEvents()
            }
        }
    }
}

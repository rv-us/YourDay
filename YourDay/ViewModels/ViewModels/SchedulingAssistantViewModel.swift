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

struct ModificationReasonInput {
    let dayOfWeek: String
    let originalTime: String
    let modifiedTime: String
    let tasks: [String]
    let originalTasks: [String]
    let addedTasks: [String]
    let removedTasks: [String]
    let reason: String
}

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
    @Published var showingRescheduleConfirmation = false
    @Published var pendingRescheduleBacklogItems: [UnifiedBacklogItem] = []
    @Published var declinedTasks: [String] = [] // Track tasks that were declined
    @Published var dayContexts: [String: DayContext] = [:]
    @Published var scheduleNotes: [ScheduleNote] = []
    @Published var recentInteractions: [ProposalInteraction] = []
    @Published var statusMessage: String? // Status message for current agent operation
    @Published var isGeneratingMemory = false // Track when memory is being generated
    /// Set when adding an event to Google Calendar fails (e.g. accept proposal or manual schedule).
    @Published var calendarOperationError: String?
    /// Set when calendar events cannot be loaded (e.g. not signed in or missing scope).
    @Published var calendarFetchError: String?

    private let firebaseManager = FirebaseManager.shared
    private let calendarManager = GoogleCalendarManager.shared

    private var conversationContext: String = ""
    private var declineReasons: [String] = [] // Persistent decline reasons derived from interactions
    
    // Session-specific tracking (cleared when session ends)
    private var sessionDeclineReasons: [String] = [] // Decline reasons from current session
    private var sessionModificationReasons: [String] = [] // Modification reasons from current session
    
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
        showingRescheduleConfirmation = false
        pendingRescheduleBacklogItems = []
        declinedTasks = []
        calendarOperationError = nil
        calendarFetchError = nil
        clearSessionContext()
    }
    
    func clearCalendarOperationError() {
        calendarOperationError = nil
    }
    
    func clearCalendarFetchError() {
        calendarFetchError = nil
    }
    
    func clearSessionContext() {
        // Clear session-specific reasons when session ends
        sessionDeclineReasons.removeAll()
        sessionModificationReasons.removeAll()
    }
    
    func addSessionModificationReason(reason: String, originalTime: String, modifiedTime: String, tasks: [String]) {
        // Track modification reason for current session
        let modificationText = "Modified \(tasks.joined(separator: ", ")) from \(originalTime) to \(modifiedTime). Reason: \(reason)"
        if !sessionModificationReasons.contains(modificationText) {
            sessionModificationReasons.append(modificationText)
        }
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
        let calendarScope = "https://www.googleapis.com/auth/calendar"
        let user = GIDSignIn.sharedInstance.currentUser
        let primaryReady = user.map { u in
            u.grantedScopes?.contains(calendarScope) == true && !u.accessToken.tokenString.isEmpty
        } ?? false
        let linkedReady = CalendarConnectionsSettingsStore.shared.linkedReadOnlyAccounts.contains {
            CalendarConnectionKeychain.loadRefreshToken(accountKey: $0.accountKey) != nil
        }

        guard primaryReady || linkedReady else {
            if user != nil {
                calendarFetchError = "Grant calendar access in Google sign-in, or add a read-only Google account in Settings → Connections."
            } else {
                calendarFetchError = "Sign in with Google and grant calendar access, or add a read-only Google account in Settings → Connections."
            }
            calendarEvents = []
            calendarFetchCompletion?()
            calendarFetchCompletion = nil
            isFetchingCalendar = false
            return
        }

        isFetchingCalendar = true
        calendarFetchError = nil
        showStatus("Fetching calendar events...")

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isFetchingCalendar = false
                self.calendarFetchCompletion?()
                self.calendarFetchCompletion = nil
            }
            do {
                let events = try await GoogleCalendarEventFetchService.fetchMergedVisibleEvents(
                    start: startOfDay,
                    end: endOfDay
                )
                self.calendarEvents = events
                self.calendarFetchError = nil
                self.clearStatus()
                print("📅 Fetched \(events.count) merged calendar events for date")
            } catch {
                self.clearStatus()
                self.calendarFetchError = "Could not load calendar: \(error.localizedDescription)"
                print("Error fetching calendar events: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Schedule Preferences
    
    func fetchSchedulePreference(completion: (() -> Void)? = nil) {
        firebaseManager.fetchSchedulePreference { [weak self] preference, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let preference = preference {
                    self.schedulePreference = preference
                } else if let userId = Auth.auth().currentUser?.uid {
                    // Create default preference
                    self.schedulePreference = UserSchedulePreference(userId: userId)
                }
                self.refreshDeclineReasonsFromInteractions()
                completion?()
            }
        }
    }
    
    func updateSchedulePreference(_ updates: [String: Any]) {
        guard Auth.auth().currentUser?.uid != nil else {
            print("⚠️ Cannot update schedule preference: User not authenticated")
            return
        }

        print("💾 Updating schedule preference with keys: \(updates.keys.joined(separator: ", "))")
        
        firebaseManager.updateSchedulePreference(updates) { [weak self] error in
            if let error = error {
                print("❌ Error updating schedule preference: \(error.localizedDescription)")
                return
            }

            print("✅ Successfully updated schedule preference in Firebase")
            
            // Refresh preference
            self?.fetchSchedulePreference()
        }
    }

    // MARK: - Memory Management

    func deleteDayOfWeekMemory(day: String, memory: String) {
        guard var currentMemories = schedulePreference?.dayOfWeekMemories else { return }
        guard var dayMemories = currentMemories[day] else { return }
        
        dayMemories.removeAll { $0 == memory }
        if dayMemories.isEmpty {
            currentMemories.removeValue(forKey: day)
        } else {
            currentMemories[day] = dayMemories
        }
        
        updateSchedulePreference(["dayOfWeekMemories": currentMemories])
    }

    func editDayOfWeekMemory(day: String, oldMemory: String, newMemory: String) {
        guard var currentMemories = schedulePreference?.dayOfWeekMemories else { return }
        guard var dayMemories = currentMemories[day] else { return }
        
        if let index = dayMemories.firstIndex(of: oldMemory) {
            dayMemories[index] = newMemory
            currentMemories[day] = dayMemories
            updateSchedulePreference(["dayOfWeekMemories": currentMemories])
        }
    }

    func deleteScheduleConstraint(at index: Int) {
        guard var constraints = schedulePreference?.scheduleConstraints else { return }
        guard index >= 0 && index < constraints.count else { return }
        
        constraints.remove(at: index)
        
        let constraintsDicts = constraints.map { c in
            var dict: [String: Any] = ["reason": c.reason]
            if let timeRange = c.timeRange { dict["timeRange"] = timeRange }
            if let context = c.context { dict["context"] = context }
            return dict
        }
        
        updateSchedulePreference(["scheduleConstraints": constraintsDicts])
    }
    
    func editScheduleConstraint(at index: Int, newConstraint: ScheduleConstraint) {
        guard var constraints = schedulePreference?.scheduleConstraints else { return }
        guard index >= 0 && index < constraints.count else { return }
        
        constraints[index] = newConstraint
        
        let constraintsDicts = constraints.map { c in
            var dict: [String: Any] = ["reason": c.reason]
            if let timeRange = c.timeRange { dict["timeRange"] = timeRange }
            if let context = c.context { dict["context"] = context }
            return dict
        }
        
        updateSchedulePreference(["scheduleConstraints": constraintsDicts])
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
                    self.refreshDeclineReasonsFromInteractions()
                }
            }
        }
    }

    private func refreshDeclineReasonsFromInteractions() {
        var reasons = recentInteractions
            .filter { $0.action == .declined }
            .compactMap { $0.declineReason?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let learnedPatterns = schedulePreference?.learnedPatterns {
            for (key, value) in learnedPatterns where key.hasPrefix("decline_reason_") {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    reasons.append(trimmed)
                }
            }
        }

        var seen = Set<String>()
        declineReasons = reasons.filter { seen.insert($0).inserted }
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

    private func formatDayOfWeekMemories(for dayOfWeek: String) -> String {
        guard let memories = schedulePreference?.dayOfWeekMemories?[dayOfWeek.lowercased()], !memories.isEmpty else {
            return "None"
        }

        return memories.map { "- \($0)" }.joined(separator: "\n")
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

            // Persistent decline reasons from history
            let declineReasonsText = self.declineReasons.isEmpty ? "None" : self.declineReasons.joined(separator: "; ")
            // Session-specific decline reasons
            let sessionDeclineReasonsText = self.sessionDeclineReasons.isEmpty ? "None" : self.sessionDeclineReasons.joined(separator: "; ")
            
            // Format session-specific modification reasons
            let sessionModificationReasonsText = self.sessionModificationReasons.isEmpty ? "None" : self.sessionModificationReasons.joined(separator: "\n")

            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .full
            let dateString = dateFormatter.string(from: date)

            // Get day-specific context
            let dayOfWeek = self.getDayOfWeekString(from: date)
            let dayContext = self.dayContexts[dayOfWeek]
            let dayContextText = self.formatDayContext(dayContext, dayOfWeek: dayOfWeek)
            let dayOfWeekMemoriesText = self.formatDayOfWeekMemories(for: dayOfWeek)

            // Get schedule notes for this date
            let scheduleNotesText = self.formatScheduleNotes()

            // Get recent interactions for learning (only from this specific date)
            let interactionHistoryText = self.formatRecentInteractions(for: date)

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
            IMPORTANT: Each line shows a time range. Lines ending with ": nothing" indicate FREE time. Lines with any other text (event names, "blocked", "lunch", etc.) indicate BUSY time. You can ONLY propose working sessions during periods marked ": nothing".
            \(timeSlots)

            Day-Specific Context for \(dayOfWeek.capitalized):
            \(dayContextText)

            Learned Day-of-Week Memories for \(dayOfWeek.capitalized):
            \(dayOfWeekMemoriesText)

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

            Session-Specific Information (from this planning session):
            - Decline Reasons: \(sessionDeclineReasonsText)
            - Modification Reasons: \(sessionModificationReasonsText)
            
            IMPORTANT: The session-specific information above contains real-time feedback from this session. For example, if the user mentioned they're meeting a friend at 1 PM, you MUST account for that when proposing future events in this session.

            User's Interaction History (from this specific date - \(dateString)):
            \(interactionHistoryText)
            
            NOTE: For general day-of-week patterns, refer to the "Learned Day-of-Week Memories" section above.

            User's Preference Statistics:
            \(acceptanceStatsText)

            Instructions:
            1. Analyze the backlog items and identify tasks that can be grouped together into one working session:
               - BATCH quick tasks (<15 min each) together into one session
               - GROUP tasks by category when they're related
               - Keep SINGLE focus tasks that need dedicated attention separate
            2. Consider task priorities (higher number = higher priority) and estimated durations
            3. FINDING AN AVAILABLE TIME SLOT - FOLLOW THESE STEPS EXACTLY:
               STEP 3A: Read the "Calendar Time Slots" section above. Each line shows a time range in the format: "START TIME to END TIME: DESCRIPTION"
               STEP 3B: Look for lines where the description says "nothing" - these are FREE periods. Lines with event names, "blocked", "lunch", or any other text are BUSY periods.
               STEP 3C: For each FREE period (marked "nothing"), calculate the duration:
                 - Example: "2:00 PM to 3:30 PM: nothing" = 90 minutes of free time
                 - Example: "9:00 AM to 10:15 AM: nothing" = 75 minutes of free time
               STEP 3D: Compare the FREE period duration to your total task duration needed:
                 - Add up all estimated durations for the tasks you want to schedule
                 - Add 15-30 minutes buffer time
                 - The free period must be LONGER than or EQUAL to this total duration
               STEP 3E: Verify NO CONFLICTS by checking:
                 - The proposed start time must be WITHIN a "nothing" period
                 - The proposed end time must also be WITHIN the same "nothing" period
                 - DO NOT propose times that overlap with ANY event, blocked time, lunch, or wake time
               STEP 3F: If today, ensure the start time is AFTER the current time shown above
               STEP 3G: ONLY propose times that are explicitly shown as "nothing" in the calendar. DO NOT invent or assume free time exists.
               STEP 3H: If no suitable free period exists, you may need to split tasks or propose a shorter session that fits available time.
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
                    
                    // DEBUG: Print exact prompt sent to Gemini
                    print(String(repeating: "=", count: 80))
                    print("🔵 GEMINI PROMPT - proposeWorkingSession")
                    print(String(repeating: "=", count: 80))
                    print(prompt)
                    print(String(repeating: "=", count: 80))
                    
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

    private func formatRecentInteractions(for date: Date) -> String {
        let calendar = Calendar.current
        let targetDateStart = calendar.startOfDay(for: date)
        let targetDateEnd = calendar.date(byAdding: .day, value: 1, to: targetDateStart) ?? date
        
        // Filter interactions to only include those from the specific date being planned
        let relevantInteractions = recentInteractions.filter { interaction in
            let interactionDate = interaction.timestamp
            return interactionDate >= targetDateStart && interactionDate < targetDateEnd
        }

        guard !relevantInteractions.isEmpty else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            return "No previous interactions on \(dateFormatter.string(from: date))"
        }

        return relevantInteractions.prefix(5).map { interaction in
            var line = "- \(interaction.action.rawValue.capitalized)"
            // Include task names
            let tasksText = interaction.proposedTasks.isEmpty ? "No tasks" : interaction.proposedTasks.joined(separator: ", ")
            line += " tasks: [\(tasksText)]"
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
        
        // If this is a decline reason, save it and ask user if they want to reschedule
        if showingDeclineReasonInput {
            let trimmedReason = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedReason.isEmpty {
                sessionDeclineReasons.append(trimmedReason)
                
                // Save to preferences
                var learnedPatterns = schedulePreference?.learnedPatterns ?? [:]
                learnedPatterns["decline_reason_\(UUID().uuidString)"] = trimmedReason
                updateSchedulePreference(["learnedPatterns": learnedPatterns])
            }
            showingDeclineReasonInput = false
            declineReason = ""
            
            // Store declined tasks before clearing proposal
            if let proposal = currentProposal {
                declinedTasks = proposal.tasks
                
                let duration = proposal.effectiveDuration ?? 60
                let interaction = ProposalInteraction(
                    proposedTasks: proposal.tasks,
                    proposedTime: proposal.workingSessionTime,
                    proposedDuration: duration,
                    action: .declined,
                    modifiedTime: nil,
                    modifiedDuration: nil,
                    declineReason: trimmedReason.isEmpty ? nil : trimmedReason,
                    dayOfWeek: getDayOfWeekString(from: selectedDate)
                )
                recordInteraction(interaction)
            }
            
            // Clear current proposal
            currentProposal = nil
            
            // Store backlog items and show confirmation dialog instead of automatically rescheduling
            pendingRescheduleBacklogItems = backlogItems
            showingRescheduleConfirmation = true
            
            completion(nil)
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
                // DEBUG: Print exact prompt sent to Gemini
                print(String(repeating: "=", count: 80))
                print("🟢 GEMINI PROMPT - sendMessage")
                print(String(repeating: "=", count: 80))
                print(prompt)
                print(String(repeating: "=", count: 80))
                
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
        calendarOperationError = nil

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
            let tasksTitle: String
            switch proposal.tasks.count {
            case 0:
                tasksTitle = "Working Session"
            case 1:
                tasksTitle = proposal.tasks.first ?? "Working Session"
            case 2...3:
                // Join 2-3 tasks with " & "
                tasksTitle = proposal.tasks.joined(separator: " & ")
            default:
                // For 4+ tasks, show first 2 tasks with " & X more"
                let maxTitleLength = 60
                let firstTwo = Array(proposal.tasks.prefix(2))
                var title = firstTwo.joined(separator: ", ")
                let remaining = proposal.tasks.count - 2
                let moreText = " & \(remaining) more"
                
                // If adding "more" would exceed length, use just first task
                if title.count + moreText.count > maxTitleLength {
                    title = firstTwo[0]
                    let newRemaining = proposal.tasks.count - 1
                    tasksTitle = "\(title) & \(newRemaining) more"
                } else {
                    tasksTitle = title + moreText
                }
            }
            let tasksDescription = proposal.tasks.joined(separator: "\n• ")
            // Add marker to identify this as a scheduled task from smart scheduling
            let scheduledTaskMarker = "\n\n[YourDay Scheduled Task]"
            let fullDescription = "Tasks:\n• \(tasksDescription)\n\n\(proposal.reason ?? "")\(scheduledTaskMarker)"

            calendarManager.ensureCalendarWriteAccess { [weak self] accessResult in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    switch accessResult {
                    case .failure(let err):
                        self.calendarOperationError = err.localizedDescription
                        onComplete([])
                    case .success:
                        self.calendarManager.createCalendarEvent(
                            title: tasksTitle,
                            start: adjustedStartTime,
                            end: adjustedEndTime,
                            description: fullDescription
                        ) { [weak self] eventId, error in
                            guard let self = self else { return }
                            DispatchQueue.main.async {
                                if let error = error {
                                    print("Error creating calendar event: \(error.localizedDescription)")
                                    self.calendarOperationError = error.localizedDescription
                                    onComplete([])
                                    return
                                }
                                guard let eventId = eventId, !eventId.isEmpty else {
                                    self.calendarOperationError = "Could not confirm the calendar event."
                                    onComplete([])
                                    return
                                }

                                self.firebaseManager.saveScheduledEvent(
                                    eventId: eventId,
                                    taskTitle: tasksTitle,
                                    tasks: proposal.tasks,
                                    startTime: adjustedStartTime,
                                    endTime: adjustedEndTime
                                ) { [weak self] saveError in
                                    guard let self = self else { return }
                                    DispatchQueue.main.async {
                                        if let saveError = saveError {
                                            print("Error saving scheduled event mapping: \(saveError.localizedDescription)")
                                            self.calendarOperationError = saveError.localizedDescription
                                            onComplete([])
                                            return
                                        }

                                        print("✅ Created working session calendar event")
                                        NotificationManager.shared.scheduleJournalPromptNotification(
                                            eventId: eventId,
                                            taskTitle: tasksTitle,
                                            scheduledEndTime: adjustedEndTime
                                        )

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

                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                            self.fetchCalendarEvents(for: self.selectedDate)

                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
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
                            }
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

    func declineProposal() {
        guard currentProposal != nil else { return }
        showingDeclineReasonInput = true
    }

    func submitDeclineReason(_ reason: String?, backlogItems: [UnifiedBacklogItem]) {
        let trimmedReason = (reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        showingDeclineReasonInput = false
        declineReason = ""

        guard let proposal = currentProposal else { return }

        if !trimmedReason.isEmpty {
            sessionDeclineReasons.append(trimmedReason)

            var learnedPatterns = schedulePreference?.learnedPatterns ?? [:]
            learnedPatterns["decline_reason_\(UUID().uuidString)"] = trimmedReason
            updateSchedulePreference(["learnedPatterns": learnedPatterns])
        }

        declinedTasks = proposal.tasks

        let duration = proposal.effectiveDuration ?? 60
        let interaction = ProposalInteraction(
            proposedTasks: proposal.tasks,
            proposedTime: proposal.workingSessionTime,
            proposedDuration: duration,
            action: .declined,
            modifiedTime: nil,
            modifiedDuration: nil,
            declineReason: trimmedReason.isEmpty ? nil : trimmedReason,
            dayOfWeek: getDayOfWeekString(from: selectedDate)
        )
        recordInteraction(interaction)

        currentProposal = nil
        pendingRescheduleBacklogItems = backlogItems
        showingRescheduleConfirmation = true
    }

    func cancelDeclineReason() {
        showingDeclineReasonInput = false
        declineReason = ""
    }
    
    func confirmReschedule(completion: @escaping (Error?) -> Void) {
        showingRescheduleConfirmation = false
        let backlogItems = pendingRescheduleBacklogItems
        pendingRescheduleBacklogItems = []
        declinedTasks = [] // Clear declined tasks when rescheduling
        
        // Propose another time
        proposeWorkingSession(backlogItems: backlogItems, completion: completion)
    }
    
    func cancelReschedule() {
        showingRescheduleConfirmation = false
        pendingRescheduleBacklogItems = []
        declinedTasks = [] // Clear declined tasks
    }
    
    func getDeclinedTasks() -> [String] {
        return declinedTasks
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

    // MARK: - Decline Reason Learning
    
    func analyzeDeclineReasonsBatch() {
        // Refresh recent interactions to ensure we have the latest data
        fetchRecentInteractions()
        
        // Get all declined interactions from recent interactions
        // Use a small delay to ensure fetchRecentInteractions completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            
            let declinedInteractions = self.recentInteractions.filter { interaction in
                interaction.action == .declined && interaction.declineReason != nil && !interaction.declineReason!.isEmpty
            }
            
            guard !declinedInteractions.isEmpty else { return }
            
            // Group by day of week
            let grouped = Dictionary(grouping: declinedInteractions, by: { $0.dayOfWeek.lowercased() })
            let groupedSummary = grouped.keys.sorted().map { day in
                let items = grouped[day, default: []]
                let lines = items.map { interaction in
                    "- Tasks: \(interaction.proposedTasks.joined(separator: ", ")); Time: \(interaction.proposedTime); Reason: \(interaction.declineReason ?? "No reason")"
                }.joined(separator: "\n")
                return "\(day.capitalized):\n\(lines)"
            }.joined(separator: "\n\n")
            
            let analysisPrompt = """
            The user declined several scheduled sessions with reasons. Extract day-of-week specific memories and schedule constraints that can guide future scheduling.

            Declined sessions grouped by day of week:
            \(groupedSummary)

            Return JSON in this format:
            {
                "dayOfWeekMemories": {
                    "monday": ["Memory 1", "Memory 2"],
                    "tuesday": ["Memory 1"]
                },
                "scheduleConstraints": [
                    {
                        "reason": "Brief description of the constraint",
                        "timeRange": "Affected time range if specific (e.g., '14:00-15:00') or null",
                        "context": "Additional context or null"
                    }
                ]
            }

            Only include days that have meaningful, actionable memories. Keep memories short and specific.
            Extract constraints that appear multiple times or are clearly stated.
            """
            
            Task {
                do {
                    // DEBUG: Print exact prompt sent to Gemini
                    print(String(repeating: "=", count: 80))
                    print("🔴 GEMINI PROMPT - analyzeDeclineReasonsBatch")
                    print(String(repeating: "=", count: 80))
                    print(analysisPrompt)
                    print(String(repeating: "=", count: 80))
                    
                    let vertex = VertexAI.vertexAI()
                    let model = vertex.generativeModel(modelName: "gemini-2.5-flash")
                    
                    let analysisMessage = ModelContent(role: "user", parts: [TextPart(analysisPrompt)])
                    let response = try await model.generateContent([analysisMessage])
                    
                    guard let text = response.text,
                          let data = text.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        return
                    }
                    
                    // Update day-of-week memories
                    if let memories = json["dayOfWeekMemories"] as? [String: [String]] {
                        var updatedMemories = self.schedulePreference?.dayOfWeekMemories ?? [:]
                        for (day, dayMemories) in memories {
                            let normalizedDay = day.lowercased()
                            let existing = updatedMemories[normalizedDay] ?? []
                            let merged = existing + dayMemories.filter { !existing.contains($0) }
                            updatedMemories[normalizedDay] = merged
                        }
                        self.updateSchedulePreference(["dayOfWeekMemories": updatedMemories])
                        DispatchQueue.main.async {
                            self.schedulePreference?.dayOfWeekMemories = updatedMemories
                        }
                    }
                    
                    // Update schedule constraints
                    if let constraintsArray = json["scheduleConstraints"] as? [[String: Any]] {
                        self.firebaseManager.fetchSchedulePreference { [weak self] preference, _ in
                            guard let self = self, let pref = preference else { return }
                            
                            var constraints = pref.scheduleConstraints
                            for constraintDict in constraintsArray {
                                if let reason = constraintDict["reason"] as? String {
                                    let constraint = ScheduleConstraint(
                                        reason: reason,
                                        timeRange: constraintDict["timeRange"] as? String,
                                        context: constraintDict["context"] as? String
                                    )
                                    // Only add if not already present (simple deduplication)
                                    if !constraints.contains(where: { $0.reason == reason && $0.timeRange == constraint.timeRange }) {
                                        constraints.append(constraint)
                                    }
                                }
                            }
                            
                            let constraintsDicts = constraints.map { c in
                                var dict: [String: Any] = ["reason": c.reason]
                                if let timeRange = c.timeRange { dict["timeRange"] = timeRange }
                                if let context = c.context { dict["context"] = context }
                                return dict
                            }
                            
                            self.updateSchedulePreference(["scheduleConstraints": constraintsDicts])
                            DispatchQueue.main.async {
                                self.schedulePreference?.scheduleConstraints = constraints
                            }
                        }
                    }
                } catch {
                    print("Error analyzing decline reasons batch: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Modification Reason Learning

    func saveModificationReason(reason: String, originalTime: String, modifiedTime: String, tasks: [String]) {
        guard !reason.isEmpty else { return }

        // Save to learned patterns
        var learnedPatterns = schedulePreference?.learnedPatterns ?? [:]
        let key = "modification_\(Date().timeIntervalSince1970)"
        learnedPatterns[key] = reason
        updateSchedulePreference(["learnedPatterns": learnedPatterns])

        // Analyze the reason to extract schedule constraints
        analyzeModificationReason(reason: reason, originalTime: originalTime, modifiedTime: modifiedTime, tasks: tasks)

        // Save a message for context
        if let userId = Auth.auth().currentUser?.uid {
            let message = SchedulingMessage(
                userId: userId,
                role: .user,
                content: "Modified \(tasks.joined(separator: ", ")) from \(originalTime) to \(modifiedTime). Reason: \(reason)"
            )
            messages.append(message)
            firebaseManager.saveSchedulingMessage(message) { _ in }
        }
    }

    func analyzeModificationReasonsBatch(_ modifications: [ModificationReasonInput]) {
        let trimmedModifications = modifications.compactMap { modification -> ModificationReasonInput? in
            let trimmedReason = modification.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedReason.isEmpty else { return nil }
            
            return ModificationReasonInput(
                dayOfWeek: modification.dayOfWeek,
                originalTime: modification.originalTime,
                modifiedTime: modification.modifiedTime,
                tasks: modification.tasks,
                originalTasks: modification.originalTasks,
                addedTasks: modification.addedTasks,
                removedTasks: modification.removedTasks,
                reason: trimmedReason
            )
        }

        guard !trimmedModifications.isEmpty else { return }

        // Persist raw modification reasons for history
        var learnedPatterns = schedulePreference?.learnedPatterns ?? [:]
        for modification in trimmedModifications {
            learnedPatterns["modification_reason_\(UUID().uuidString)"] = modification.reason
        }
        updateSchedulePreference(["learnedPatterns": learnedPatterns])

        let grouped = Dictionary(grouping: trimmedModifications, by: { $0.dayOfWeek.lowercased() })
        let groupedSummary = grouped.keys.sorted().map { day in
            let items = grouped[day, default: []]
            let lines = items.map { item in
                var taskInfo = "Tasks: \(item.tasks.joined(separator: ", "))"
                
                // Add task change information
                if !item.addedTasks.isEmpty {
                    taskInfo += "; Added: \(item.addedTasks.joined(separator: ", "))"
                }
                if !item.removedTasks.isEmpty {
                    taskInfo += "; Removed: \(item.removedTasks.joined(separator: ", "))"
                }
                
                return "- \(taskInfo); Original: \(item.originalTime); Modified: \(item.modifiedTime); Reason: \(item.reason)"
            }.joined(separator: "\n")
            return "\(day.capitalized):\n\(lines)"
        }.joined(separator: "\n\n")

        let analysisPrompt = """
        The user provided reasons for modifying scheduled sessions. Extract day-of-week specific memories that can guide future scheduling.

        Reasons grouped by day of week:
        \(groupedSummary)

        Return JSON in this format:
        {
            "dayOfWeekMemories": {
                "monday": ["Memory 1", "Memory 2"],
                "tuesday": ["Memory 1"]
            },
            "scheduleConstraints": [
                {
                    "reason": "Brief description of the constraint",
                    "timeRange": "Affected time range if specific (e.g., '14:00-15:00') or null",
                    "context": "Additional context or null"
                }
            ]
        }

        Only include days that have meaningful, actionable memories. Keep memories short and specific.
        Note: When tasks were added or removed, consider this in the memory extraction (e.g., "User prefers not to group food tasks with other tasks").
        Only include schedule constraints that are clearly stated or repeated. If none, return an empty array.
        """

        Task {
            await MainActor.run {
                isGeneratingMemory = true
            }
            
            do {
                // DEBUG: Print exact prompt sent to Gemini
                print(String(repeating: "=", count: 80))
                print("🟣 GEMINI PROMPT - analyzeModificationReasonsBatch")
                print(String(repeating: "=", count: 80))
                print(analysisPrompt)
                print(String(repeating: "=", count: 80))
                
                let vertex = VertexAI.vertexAI()
                let model = vertex.generativeModel(modelName: "gemini-2.5-flash")

                let analysisMessage = ModelContent(role: "user", parts: [TextPart(analysisPrompt)])
                let response = try await model.generateContent([analysisMessage])

                // DEBUG: Print Gemini output
                guard let responseText = response.text else {
                    print("⚠️ No response text from Gemini")
                    await MainActor.run {
                        isGeneratingMemory = false
                    }
                    return
                }
                
                print(String(repeating: "=", count: 80))
                print("🟣 GEMINI OUTPUT - analyzeModificationReasonsBatch")
                print(String(repeating: "=", count: 80))
                print(responseText)
                print(String(repeating: "=", count: 80))
                
                // Extract JSON from markdown code blocks if present
                guard let jsonText = extractJSONFromResponse(responseText),
                      let jsonData = jsonText.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                    print("⚠️ Failed to parse JSON from Gemini response")
                    if let jsonText = extractJSONFromResponse(responseText) {
                        print("Extracted JSON text: \(jsonText)")
                    }
                    await MainActor.run {
                        isGeneratingMemory = false
                    }
                    return
                }

                if let memories = json["dayOfWeekMemories"] as? [String: [String]] {
                    print("✅ Successfully parsed \(memories.count) day(s) of memories from Gemini response")

                    var updatedMemories = schedulePreference?.dayOfWeekMemories ?? [:]
                    for (day, dayMemories) in memories {
                        let normalizedDay = day.lowercased()
                        let existing = updatedMemories[normalizedDay] ?? []
                        let merged = existing + dayMemories.filter { !existing.contains($0) }
                        updatedMemories[normalizedDay] = merged
                        print("📝 Updated memories for \(normalizedDay): \(merged.count) total (\(dayMemories.count) new)")
                    }

                    updateSchedulePreference(["dayOfWeekMemories": updatedMemories])
                    await MainActor.run {
                        self.schedulePreference?.dayOfWeekMemories = updatedMemories
                    }
                    print("💾 Saved dayOfWeekMemories to Firebase")
                } else {
                    print("⚠️ No dayOfWeekMemories found in Gemini response")
                }

                if let constraintsArray = json["scheduleConstraints"] as? [[String: Any]],
                   !constraintsArray.isEmpty {
                    self.firebaseManager.fetchSchedulePreference { [weak self] preference, _ in
                        guard let self = self, let pref = preference else { return }

                        var constraints = pref.scheduleConstraints
                        for constraintDict in constraintsArray {
                            if let reason = constraintDict["reason"] as? String {
                                let constraint = ScheduleConstraint(
                                    reason: reason,
                                    timeRange: constraintDict["timeRange"] as? String,
                                    context: constraintDict["context"] as? String
                                )
                                if !constraints.contains(where: { $0.reason == reason && $0.timeRange == constraint.timeRange }) {
                                    constraints.append(constraint)
                                }
                            }
                        }

                        let constraintsDicts = constraints.map { c in
                            var dict: [String: Any] = ["reason": c.reason]
                            if let timeRange = c.timeRange { dict["timeRange"] = timeRange }
                            if let context = c.context { dict["context"] = context }
                            return dict
                        }

                        self.updateSchedulePreference(["scheduleConstraints": constraintsDicts])
                        DispatchQueue.main.async {
                            self.schedulePreference?.scheduleConstraints = constraints
                        }
                    }
                }
                
                await MainActor.run {
                    isGeneratingMemory = false
                }
            } catch {
                print("Error analyzing modification reasons batch: \(error.localizedDescription)")
                await MainActor.run {
                    isGeneratingMemory = false
                }
            }
        }
    }

    // MARK: - JSON Extraction Helper
    
    private func extractJSONFromResponse(_ text: String) -> String? {
        // Check for markdown code blocks with json
        if text.contains("```json") {
            // Extract content between ```json and ```
            let pattern = #"```json\s*(.*?)\s*```"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
                let nsString = text as NSString
                let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
                
                if let match = results.first, match.numberOfRanges > 1 {
                    let jsonRange = match.range(at: 1)
                    if jsonRange.location != NSNotFound {
                        let jsonContent = nsString.substring(with: jsonRange)
                        return jsonContent.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
            
            // Fallback: simple string replacement if regex fails
            return text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // If no markdown, return as-is
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func analyzeModificationReason(reason: String, originalTime: String, modifiedTime: String, tasks: [String]) {
        let analysisPrompt = """
        The user modified a scheduled working session. Analyze their reason to extract scheduling preferences.

        Original time: \(originalTime)
        Modified to: \(modifiedTime)
        Tasks: \(tasks.joined(separator: ", "))
        User's reason: "\(reason)"

        Extract any schedule constraints or preferences. Return JSON:
        {
            "scheduleConstraint": {
                "reason": "Brief description of the constraint",
                "timeRange": "Affected time range if specific (e.g., '14:00-15:00') or null",
                "context": "Additional context or null"
            } or null,
            "preferenceUpdate": {
                "type": "preferEarlier" or "preferLater" or "avoidTime" or "preferDuration" or null,
                "value": "Specific preference value if applicable"
            } or null
        }

        If no clear constraint can be extracted, return {"scheduleConstraint": null, "preferenceUpdate": null}
        """

        Task {
            do {
                // DEBUG: Print exact prompt sent to Gemini
                print(String(repeating: "=", count: 80))
                print("🟡 GEMINI PROMPT - analyzeModificationReason")
                print(String(repeating: "=", count: 80))
                print(analysisPrompt)
                print(String(repeating: "=", count: 80))
                
                let vertex = VertexAI.vertexAI()
                let model = vertex.generativeModel(modelName: "gemini-2.5-flash")

                let analysisMessage = ModelContent(role: "user", parts: [TextPart(analysisPrompt)])
                let response = try await model.generateContent([analysisMessage])

                guard let text = response.text,
                      let data = text.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return
                }

                // Extract and save schedule constraint
                if let constraintDict = json["scheduleConstraint"] as? [String: Any],
                   let constraintReason = constraintDict["reason"] as? String {
                    let constraint = ScheduleConstraint(
                        reason: constraintReason,
                        timeRange: constraintDict["timeRange"] as? String,
                        context: constraintDict["context"] as? String
                    )

                    // Add to existing constraints
                    firebaseManager.fetchSchedulePreference { [weak self] preference, _ in
                        guard let self = self, let pref = preference else { return }

                        var constraints = pref.scheduleConstraints
                        constraints.append(constraint)

                        let constraintsDicts = constraints.map { c in
                            var dict: [String: Any] = ["reason": c.reason]
                            if let timeRange = c.timeRange { dict["timeRange"] = timeRange }
                            if let context = c.context { dict["context"] = context }
                            return dict
                        }

                        self.updateSchedulePreference(["scheduleConstraints": constraintsDicts])
                    }
                }

                // Handle preference updates (e.g., user prefers earlier times)
                if let prefUpdate = json["preferenceUpdate"] as? [String: Any],
                   let prefType = prefUpdate["type"] as? String {
                    var learnedPatterns = schedulePreference?.learnedPatterns ?? [:]
                    learnedPatterns["preference_\(prefType)"] = prefUpdate["value"] as? String ?? "true"
                    updateSchedulePreference(["learnedPatterns": learnedPatterns])
                }
            } catch {
                print("Error analyzing modification reason: \(error.localizedDescription)")
            }
        }
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
                // DEBUG: Print exact prompt sent to Gemini
                print(String(repeating: "=", count: 80))
                print("🟠 GEMINI PROMPT - analyzeAndUpdatePreferences")
                print(String(repeating: "=", count: 80))
                print(analysisPrompt)
                print(String(repeating: "=", count: 80))
                
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
    
    // MARK: - Journal Entry Analysis
    
    func analyzeJournalEntriesBatch() {
        // Fetch recent journal entries
        firebaseManager.fetchJournalEntries { [weak self] entries, error in
            guard let self = self, let entries = entries, !entries.isEmpty else {
                if let error = error {
                    print("Error fetching journal entries for analysis: \(error.localizedDescription)")
                }
                return
            }
            
            // Use recent entries (last 30 days or last 20 entries, whichever is more)
            let calendar = Calendar.current
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            let recentEntries = entries.filter { $0.timestamp >= thirtyDaysAgo }.prefix(20)
            
            guard !recentEntries.isEmpty else { return }
            
            // Group entries by day of week
            let grouped = Dictionary(grouping: Array(recentEntries), by: { $0.dayOfWeek.lowercased() })
            
            // Build summary for AI analysis
            let entriesSummary = grouped.keys.sorted().map { day in
                let dayEntries = grouped[day, default: []]
                let lines = dayEntries.map { entry in
                    var line = "- Task: \(entry.taskTitle); "
                    line += "Scheduled: \(self.formatTimeRange(entry.scheduledStartTime, end: entry.scheduledEndTime)); "
                    if let actualStart = entry.actualStartTime, let actualEnd = entry.actualEndTime {
                        line += "Actual: \(self.formatTimeRange(actualStart, end: actualEnd)); "
                    }
                    line += "Status: \(entry.completionStatus.rawValue); "
                    line += "What did: \(entry.whatDid)"
                    if let howWent = entry.howWent, !howWent.isEmpty {
                        line += "; How went: \(howWent)"
                    }
                    if let learned = entry.learned, !learned.isEmpty {
                        line += "; Learned: \(learned)"
                    }
                    if let distractions = entry.distractions, !distractions.isEmpty {
                        line += "; Distractions: \(distractions)"
                    }
                    return line
                }.joined(separator: "\n")
                return "\(day.capitalized):\n\(lines)"
            }.joined(separator: "\n\n")
            
            // Calculate duration accuracy statistics
            let durationStats = recentEntries.compactMap { entry -> (scheduled: Int, actual: Int)? in
                guard let actualStart = entry.actualStartTime,
                      let actualEnd = entry.actualEndTime else { return nil }
                let scheduledDuration = Int(entry.scheduledEndTime.timeIntervalSince(entry.scheduledStartTime) / 60)
                let actualDuration = Int(actualEnd.timeIntervalSince(actualStart) / 60)
                return (scheduledDuration, actualDuration)
            }
            
            let avgScheduledDuration = durationStats.isEmpty ? 0 : durationStats.map { $0.scheduled }.reduce(0, +) / durationStats.count
            let avgActualDuration = durationStats.isEmpty ? 0 : durationStats.map { $0.actual }.reduce(0, +) / durationStats.count
            let durationAccuracy = durationStats.isEmpty ? "N/A" : "Average scheduled: \(avgScheduledDuration) min, Average actual: \(avgActualDuration) min"
            
            // Calculate completion rates by time of day
            let completionByHour = Dictionary(grouping: recentEntries, by: { Calendar.current.component(.hour, from: $0.scheduledStartTime) })
            let completionRates = completionByHour.map { hour, entries in
                let completed = entries.filter { $0.completionStatus == .completed }.count
                let rate = Double(completed) / Double(entries.count) * 100
                return "\(hour):00 - \(completed)/\(entries.count) completed (\(String(format: "%.0f", rate))%)"
            }.sorted().joined(separator: "\n")
            
            let analysisPrompt = """
            Analyze the user's journal entries to extract productivity patterns, scheduling preferences, and insights that can improve future task scheduling.

            Journal entries grouped by day of week:
            \(entriesSummary)

            Duration Accuracy:
            \(durationAccuracy)

            Completion Rates by Hour:
            \(completionRates.isEmpty ? "No data" : completionRates)

            Return JSON in this format:
            {
                "dayOfWeekMemories": {
                    "monday": ["Memory 1", "Memory 2"],
                    "tuesday": ["Memory 1"]
                },
                "scheduleConstraints": [
                    {
                        "reason": "Brief description of the constraint",
                        "timeRange": "Affected time range if specific (e.g., '14:00-15:00') or null",
                        "context": "Additional context or null"
                    }
                ],
                "productivityPatterns": {
                    "bestHours": [9, 10, 14],
                    "worstHours": [15, 16],
                    "preferredTaskTypes": ["coding", "writing"],
                    "commonDistractions": ["phone", "meetings"]
                },
                "durationAdjustments": {
                    "taskType": "general",
                    "multiplier": 1.2,
                    "reason": "Users typically need 20% more time than scheduled"
                }
            }

            Extract:
            1. Day-of-week specific patterns (e.g., "User is more productive on Mondays", "User struggles with focus on Fridays")
            2. Schedule constraints from distractions and completion issues
            3. Productivity patterns (best/worst hours, preferred task types)
            4. Duration adjustments based on actual vs scheduled time

            Only include meaningful, actionable insights. Keep memories short and specific.
            """
            
            Task {
                do {
                    // DEBUG: Print exact prompt sent to Gemini
                    print(String(repeating: "=", count: 80))
                    print("📔 GEMINI PROMPT - analyzeJournalEntriesBatch")
                    print(String(repeating: "=", count: 80))
                    print(analysisPrompt)
                    print(String(repeating: "=", count: 80))
                    
                    let vertex = VertexAI.vertexAI()
                    let model = vertex.generativeModel(modelName: "gemini-2.5-flash")
                    
                    let analysisMessage = ModelContent(role: "user", parts: [TextPart(analysisPrompt)])
                    let response = try await model.generateContent([analysisMessage])
                    
                    guard let text = response.text else {
                        print("⚠️ No response text from Gemini for journal analysis")
                        return
                    }
                    
                    // Extract JSON from response
                    guard let jsonText = self.extractJSONFromResponse(text),
                          let jsonData = jsonText.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                        print("⚠️ Failed to parse JSON from journal analysis response")
                        return
                    }
                    
                    // Update day-of-week memories
                    if let memories = json["dayOfWeekMemories"] as? [String: [String]] {
                        var updatedMemories = self.schedulePreference?.dayOfWeekMemories ?? [:]
                        for (day, dayMemories) in memories {
                            let normalizedDay = day.lowercased()
                            let existing = updatedMemories[normalizedDay] ?? []
                            let merged = existing + dayMemories.filter { !existing.contains($0) }
                            updatedMemories[normalizedDay] = merged
                        }
                        self.updateSchedulePreference(["dayOfWeekMemories": updatedMemories])
                        await MainActor.run {
                            self.schedulePreference?.dayOfWeekMemories = updatedMemories
                        }
                    }
                    
                    // Update schedule constraints
                    if let constraintsArray = json["scheduleConstraints"] as? [[String: Any]], !constraintsArray.isEmpty {
                        self.firebaseManager.fetchSchedulePreference { [weak self] preference, _ in
                            guard let self = self, let pref = preference else { return }
                            
                            var constraints = pref.scheduleConstraints
                            for constraintDict in constraintsArray {
                                if let reason = constraintDict["reason"] as? String {
                                    let constraint = ScheduleConstraint(
                                        reason: reason,
                                        timeRange: constraintDict["timeRange"] as? String,
                                        context: constraintDict["context"] as? String
                                    )
                                    if !constraints.contains(where: { $0.reason == reason && $0.timeRange == constraint.timeRange }) {
                                        constraints.append(constraint)
                                    }
                                }
                            }
                            
                            let constraintsDicts = constraints.map { c in
                                var dict: [String: Any] = ["reason": c.reason]
                                if let timeRange = c.timeRange { dict["timeRange"] = timeRange }
                                if let context = c.context { dict["context"] = context }
                                return dict
                            }
                            
                            self.updateSchedulePreference(["scheduleConstraints": constraintsDicts])
                            DispatchQueue.main.async {
                                self.schedulePreference?.scheduleConstraints = constraints
                            }
                        }
                    }
                    
                    // Store productivity patterns in learned patterns
                    if let productivityPatterns = json["productivityPatterns"] as? [String: Any] {
                        var learnedPatterns = self.schedulePreference?.learnedPatterns ?? [:]
                        if let bestHours = productivityPatterns["bestHours"] as? [Int] {
                            learnedPatterns["journal_best_hours"] = bestHours.map { String($0) }.joined(separator: ",")
                        }
                        if let worstHours = productivityPatterns["worstHours"] as? [Int] {
                            learnedPatterns["journal_worst_hours"] = worstHours.map { String($0) }.joined(separator: ",")
                        }
                        if let preferredTaskTypes = productivityPatterns["preferredTaskTypes"] as? [String] {
                            learnedPatterns["journal_preferred_task_types"] = preferredTaskTypes.joined(separator: ",")
                        }
                        if let commonDistractions = productivityPatterns["commonDistractions"] as? [String] {
                            learnedPatterns["journal_common_distractions"] = commonDistractions.joined(separator: ",")
                        }
                        self.updateSchedulePreference(["learnedPatterns": learnedPatterns])
                    }
                    
                    // Store duration adjustments
                    if let durationAdjustments = json["durationAdjustments"] as? [String: Any],
                       let multiplier = durationAdjustments["multiplier"] as? Double {
                        var learnedPatterns = self.schedulePreference?.learnedPatterns ?? [:]
                        learnedPatterns["journal_duration_multiplier"] = String(multiplier)
                        if let reason = durationAdjustments["reason"] as? String {
                            learnedPatterns["journal_duration_reason"] = reason
                        }
                        self.updateSchedulePreference(["learnedPatterns": learnedPatterns])
                    }
                    
                    print("✅ Successfully analyzed journal entries and updated preferences")
                } catch {
                    print("Error analyzing journal entries batch: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func formatTimeRange(_ start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: start))-\(formatter.string(from: end))"
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

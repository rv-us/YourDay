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

class SchedulingAssistantViewModel: ObservableObject {
    @Published var messages: [SchedulingMessage] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var calendarEvents: [GoogleCalendarEvent] = []
    @Published var schedulePreference: UserSchedulePreference?
    @Published var currentProposal: ProposedSession?
    @Published var showingDeclineReasonInput = false
    @Published var declineReason = ""
    
    private let firebaseManager = FirebaseManager.shared
    private let calendarManager = GoogleCalendarManager.shared
    
    private var conversationContext: String = ""
    private var declineReasons: [String] = [] // Store reasons for declined proposals
    
    func initialize(userId: String, loadHistory: Bool = true) {
        fetchSchedulePreference()
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
                print("Error fetching calendar events: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else { return }
            
            do {
                let response = try JSONDecoder().decode(GoogleCalendarResponse.self, from: data)
                DispatchQueue.main.async {
                    self.calendarEvents = response.items
                    print("📅 Fetched \(response.items.count) calendar events for date")
                }
            } catch {
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
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        firebaseManager.updateSchedulePreference(updates) { [weak self] error in
            if let error = error {
                print("Error updating schedule preference: \(error.localizedDescription)")
                return
            }
            
            // Refresh preference
            self?.fetchSchedulePreference()
        }
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
        
        // Sort events by start time
        let sortedEvents = calendarEvents.sorted { event1, event2 in
            guard let date1 = event1.start.startDate, let date2 = event2.start.startDate else { return false }
            return date1 < date2
        }
        
        var timeSlots: [String] = []
        var currentTime = startOfDay
        
        // Add wake time if set
        if let wakeTimeStr = schedulePreference?.preferredWakeTime,
           let wakeTime = parseTimeString(wakeTimeStr) {
            let wakeDate = calendar.date(bySettingHour: wakeTime.hour, minute: wakeTime.minute, second: 0, of: date) ?? startOfDay
            if wakeDate > currentTime {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                timeSlots.append("\(formatter.string(from: currentTime)) to \(formatter.string(from: wakeDate)): nothing (before wake time)")
                currentTime = wakeDate
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
        
        // Add lunch time if set
        if let lunchTimeStr = schedulePreference?.lunchTime,
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
        
        // Add remaining free time
        if currentTime < endOfDay {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            timeSlots.append("\(formatter.string(from: currentTime)) to \(formatter.string(from: endOfDay)): nothing")
        }
        
        return timeSlots.joined(separator: "\n")
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
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "SchedulingAssistantViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        selectedDate = date
        isLoading = true
        errorMessage = nil
        
        // Always refresh calendar events before proposing to get the latest schedule
        fetchCalendarEvents(for: date)
        
        // Wait a moment for calendar events to be fetched, then proceed
        // Use a completion-based approach to ensure calendar is fetched
        self.ensureCalendarFetched(for: date) {
            // Build context for AI with fresh calendar data
            let backlogText = backlogItems.map { "- \($0.title): \($0.description)" }.joined(separator: "\n")
            let timeSlots = self.formatCalendarAsTimeSlots(for: date)
            let recurringCommitmentsText = self.schedulePreference?.recurringCommitments.map { commitment in
                "- \(commitment.eventName): \(commitment.daysOfWeek.joined(separator: ", ")) at \(commitment.time)"
            }.joined(separator: "\n") ?? "None"
            
            let declineReasonsText = self.declineReasons.isEmpty ? "None" : self.declineReasons.joined(separator: "; ")
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .full
            let dateString = dateFormatter.string(from: date)
            
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
            You are a scheduling assistant. Based on the user's backlog items and their calendar for \(dateString), propose a working session.
            
            \(currentTimeContext)
            
            IMPORTANT: The calendar below shows the CURRENT state including any events that were just created. Make sure your proposed time does NOT conflict with any existing events.
            
            User's Backlog Items:
            \(backlogText.isEmpty ? "None" : backlogText)
            
            Calendar Time Slots for \(dateString) (CURRENT - includes all scheduled events):
            \(timeSlots)
            
            User's Schedule Preferences:
            - Preferred wake time: \(self.schedulePreference?.preferredWakeTime ?? "Not set")
            - Lunch time: \(self.schedulePreference?.lunchTime ?? "Not set")
            - Recurring commitments: \(recurringCommitmentsText)
            
            Learned Schedule Constraints (reasons why user can't work even when calendar is free):
            \(self.formatScheduleConstraints())
            
            Previous Decline Reasons (learn from these):
            \(declineReasonsText)
            
            Instructions:
            1. Analyze the backlog items and identify tasks that can be grouped together into one working session (e.g., similar tasks, quick tasks, related work)
            2. You can propose either:
               - A SINGLE task if it requires focused attention
               - MULTIPLE tasks (2-4 tasks) if they can be efficiently done together in one session
            3. Find an available time slot that fits the user's schedule - CHECK THE CALENDAR CAREFULLY to avoid conflicts
            4. Consider their wake time, lunch time, and any decline reasons
            5. \(isToday ? "CRITICAL: The proposed time MUST be after the current time (\(currentTimeString)). Do NOT propose any time in the past." : "Propose a time that works for the target date.")
            6. Return ONLY a JSON object with this exact format:
            {
                "tasks": ["Task 1", "Task 2", "Task 3"] or ["Single Task"],
                "workingSessionTime": "2:00 PM - 3:30 PM",
                "reason": "Brief reason why this time works and why these tasks are grouped together"
            }
            
            Do NOT include any other text, only the JSON.
            """
            
            Task {
                do {
                    let vertex = VertexAI.vertexAI()
                    let model = vertex.generativeModel(modelName: "gemini-2.5-flash")
                    
                    let userMessage = try ModelContent(role: "user", parts: [TextPart(prompt)])
                    let response = try await model.generateContent([userMessage])
                    
                    DispatchQueue.main.async {
                        self.isLoading = false
                        
                        guard let text = response.text else {
                            self.errorMessage = "AI returned no text"
                            completion(NSError(domain: "SchedulingAssistantViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "AI returned no text"]))
                            return
                        }
                        
                        // Parse JSON response
                        if let proposal = self.parseProposal(from: text) {
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
                        self.errorMessage = "Failed to generate response: \(error.localizedDescription)"
                        completion(error)
                    }
                }
            }
        }
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
            
            // Propose another time
            proposeWorkingSession(backlogItems: backlogItems, completion: completion)
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // Regular chat message - use simpler prompt
        let prompt = """
        User message: \(content)
        
        Previous conversation:
        \(conversationContext)
        
        Respond helpfully and naturally. If the user is explaining why they can't do something, acknowledge it and learn from it.
        """
        
        Task {
            do {
                let vertex = VertexAI.vertexAI()
                let model = vertex.generativeModel(modelName: "gemini-2.5-flash")
                
                let aiMessage = try ModelContent(role: "user", parts: [TextPart(prompt)])
                let response = try await model.generateContent([aiMessage])
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    
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
                    self.errorMessage = "Failed to generate response: \(error.localizedDescription)"
                    completion(error)
                }
            }
        }
    }
    
    // MARK: - Proposal Parsing
    
    private func parseProposal(from text: String) -> ProposedSession? {
        // Try to extract JSON from the response - handle multiline JSON
        let jsonPattern = "\\{[\\s\\S]*?\\}"
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
                
                return ProposedSession(
                    tasks: tasks,
                    workingSessionTime: workingSessionTime,
                    startTime: startTime,
                    endTime: endTime,
                    reason: json["reason"] as? String
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
        
        // Create calendar event for the working session
        if let startTime = proposal.startTime {
            // Adjust startTime to selected date
            let calendar = Calendar.current
            let selectedDateStart = calendar.startOfDay(for: selectedDate)
            let timeComponents = calendar.dateComponents([.hour, .minute], from: startTime)
            let adjustedStartTime = calendar.date(bySettingHour: timeComponents.hour ?? 0, minute: timeComponents.minute ?? 0, second: 0, of: selectedDateStart) ?? startTime
            
            let endTime = proposal.endTime ?? Calendar.current.date(byAdding: .hour, value: 1, to: adjustedStartTime) ?? adjustedStartTime
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
                                let message = SchedulingMessage(
                                    userId: userId,
                                    role: .user,
                                    content: "Accepted: \(tasksList) at \(proposal.workingSessionTime)"
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
    
    func declineProposal() {
        showingDeclineReasonInput = true
    }
    
    func skipTask(tasks: [String], onComplete: @escaping () -> Void) {
        // User skipped task - clear proposal and move to next task
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
    
    // MARK: - Preference Learning
    
    private func analyzeAndUpdatePreferences(userMessage: String, assistantResponse: String) {
        // Use AI to extract any schedule constraints or preferences from user message
        let analysisPrompt = """
        Analyze the following user message where they explain why they can't do a working session at a proposed time.
        The user's calendar might show the time as free, but they have personal preferences or constraints.
        
        User message: "\(userMessage)"
        
        Extract ANY schedule constraints, preferences, or reasons why they can't work at certain times:
        - Time-specific constraints (e.g., "I'm eating lunch", "I normally get up at 9 am", "I have gym at 6 pm")
        - General preferences (e.g., "I don't work after 8 pm", "I prefer mornings", "I'm not productive in the afternoon")
        - Recurring commitments that aren't on their calendar (e.g., "I have class every Monday")
        - Any other schedule-related information
        
        Respond in JSON format:
        {
            "scheduleConstraints": [
                {
                    "reason": "Brief description of why they can't work (e.g., 'I'm eating lunch', 'I normally get up at 9 am')",
                    "timeRange": "Time range if specific (e.g., '12:00-13:00', 'before 09:00', 'after 20:00') or null",
                    "context": "Additional context if needed or null"
                }
            ],
            "recurringCommitment": {
                "eventName": "Class",
                "daysOfWeek": ["MO", "WE"],
                "time": "10:00",
                "frequency": "WEEKLY"
            } or null
        }
        
        If no constraints found, return empty array for scheduleConstraints.
        """
        
        Task {
            do {
                let vertex = VertexAI.vertexAI()
                let model = vertex.generativeModel(modelName: "gemini-2.5-flash")
                
                let analysisMessage = try ModelContent(role: "user", parts: [TextPart(analysisPrompt)])
                let response = try await model.generateContent([analysisMessage])
                
                guard let text = response.text else { return }
                
                // Parse JSON response
                if let data = text.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    
                    var updates: [String: Any] = [:]
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
                    
                    // Update preferences with new constraints
                    if !constraintsToAdd.isEmpty || commitmentToAdd != nil {
                        firebaseManager.fetchSchedulePreference { [weak self] preference, _ in
                            guard let self = self, var pref = preference else { return }
                            
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

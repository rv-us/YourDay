//
//  JournalViewModel.swift
//  YourDay
//
//  ViewModel for managing journal entries
//

import Foundation
import SwiftUI
import FirebaseAuth
import Combine
import FirebaseVertexAI
import FirebaseFirestore

@MainActor
class JournalViewModel: ObservableObject {
    static let shared = JournalViewModel()
    
    @Published var journalEntries: [JournalEntry] = []
    @Published var pendingJournalPrompt: TaskEndMonitor.PendingJournalEvent?
    @Published var showingJournalPrompt = false
    @Published var pendingTaskProofCapture: TaskProofCaptureContext?
    @Published var showingTaskProofCapture = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Persisted preference - when user skips, auto-prompts are permanently disabled
    @AppStorage("autoShowJournalPrompts") var autoShowPrompts = true
    
    // Queue for pending journal events
    private var pendingJournalQueue: [TaskEndMonitor.PendingJournalEvent] = []
    
    var pendingCount: Int {
        pendingJournalQueue.count + (pendingJournalPrompt != nil ? 1 : 0)
    }
    
    private let firebaseManager = FirebaseManager.shared
    private let taskEndMonitor = TaskEndMonitor.shared
    private let notificationManager = NotificationManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var awaitingScheduledProofCaptureResolution = false
    
    private init() {
        // Observe pending journal events from TaskEndMonitor
        taskEndMonitor.$pendingJournalEvents
            .sink { [weak self] events in
                guard let self = self else { return }
                // Add all new events to queue (avoid duplicates with current prompt + queue)
                let newEvents = events.filter { !self.hasEventInPromptOrQueue(eventId: $0.eventId) }
                self.pendingJournalQueue.append(contentsOf: newEvents)

                // Show next prompt if not already showing one
                if !self.showingJournalPrompt && !self.showingTaskProofCapture {
                    self.showNextPendingPrompt()
                }
            }
            .store(in: &cancellables)
    }

    func clearError() {
        errorMessage = nil
    }
    
    private func showNextPendingPrompt() {
        guard !showingTaskProofCapture else { return }

        // Check if user has opted out of auto-prompts
        guard autoShowPrompts else {
            // User has permanently opted out of auto-prompts
            pendingJournalPrompt = nil
            showingJournalPrompt = false
            return
        }

        // Remove the next event from queue and show it
        guard !pendingJournalQueue.isEmpty else {
            pendingJournalPrompt = nil
            showingJournalPrompt = false
            return
        }
        
        // Get the next event and verify it doesn't already have a journal entry
        let nextEvent = pendingJournalQueue.removeFirst()
        
        // Double-check this event doesn't already have a journal entry
        let eventId = nextEvent.eventId
        if !eventId.isEmpty {
            firebaseManager.checkJournalEntryExists(eventId: eventId) { [weak self] exists in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if exists {
                        // This event already has a journal entry, skip it and try next
                        print("⚠️ Event \(eventId) already has journal entry, skipping")
                        self.showNextPendingPrompt()
                    } else {
                        // Safe to show this prompt
                        self.pendingJournalPrompt = nextEvent
                        self.showingJournalPrompt = true
                    }
                }
            }
        } else {
            // No eventId, show it anyway
            pendingJournalPrompt = nextEvent
            showingJournalPrompt = true
        }
    }
    
    func fetchJournalEntries() {
        guard Auth.auth().currentUser?.uid != nil else { return }
        
        isLoading = true
        errorMessage = nil
        
        firebaseManager.fetchJournalEntries { [weak self] entries, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "Error fetching journal entries: \(error.localizedDescription)"
                    print("Error fetching journal entries: \(error.localizedDescription)")
                    return
                }
                
                if let entries = entries {
                    self.journalEntries = entries
                }
            }
        }
    }
    
    func fetchJournalEntries(for date: Date) {
        guard Auth.auth().currentUser?.uid != nil else { return }
        
        isLoading = true
        errorMessage = nil
        
        firebaseManager.fetchJournalEntries(for: date) { [weak self] entries, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "Error fetching journal entries: \(error.localizedDescription)"
                    print("Error fetching journal entries: \(error.localizedDescription)")
                    return
                }
                
                if let entries = entries {
                    // Merge with existing entries, avoiding duplicates
                    let existingIds = Set(self.journalEntries.compactMap { $0.id })
                    let newEntries = entries.filter { entry in
                        guard let id = entry.id else { return true }
                        return !existingIds.contains(id)
                    }
                    self.journalEntries.append(contentsOf: newEntries)
                    self.journalEntries.sort { $0.timestamp > $1.timestamp }
                }
            }
        }
    }
    
    func saveJournalEntry(
        eventId: String?,
        taskTitle: String,
        scheduledStartTime: Date,
        scheduledEndTime: Date,
        actualStartTime: Date?,
        actualEndTime: Date?,
        whatDid: String,
        howWent: String?,
        learned: String?,
        distractions: String?,
        completionStatus: CompletionStatus
    ) {
        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = "User not authenticated"
            return
        }
        
        guard !whatDid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please describe what you did"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // Capture the eventId and current prompt at save time to prevent race conditions
        // This ensures we're journaling the correct event even if pendingJournalPrompt changes
        let savedEventId = eventId
        let currentPromptEventId = pendingJournalPrompt?.eventId
        
        // Format journal insights with LLM
        formatJournalInsights(
            whatDid: whatDid,
            howWent: howWent,
            learned: learned,
            distractions: distractions
        ) { [weak self] formattedWhatDid, formattedHowWent, formattedLearned, formattedDistractions in
            guard let self = self else { return }
            
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            let dayOfWeek = formatter.string(from: scheduledStartTime).lowercased()
            
            let entry = JournalEntry(
                userId: userId,
                eventId: savedEventId,
                taskTitle: taskTitle,
                scheduledStartTime: scheduledStartTime,
                scheduledEndTime: scheduledEndTime,
                actualStartTime: actualStartTime,
                actualEndTime: actualEndTime,
                whatDid: formattedWhatDid,
                howWent: formattedHowWent,
                learned: formattedLearned,
                distractions: formattedDistractions,
                completionStatus: completionStatus,
                dayOfWeek: dayOfWeek
            )
            
            self.firebaseManager.saveJournalEntry(entry) { [weak self] error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.isLoading = false
                    
                    if let error = error {
                        self.errorMessage = "Error saving journal entry: \(error.localizedDescription)"
                        print("Error saving journal entry: \(error.localizedDescription)")
                        return
                    }
                    
                    // Mark event as journaled - only mark the specific eventId that was saved
                    // Use the captured eventId to prevent issues if pendingJournalPrompt changed
                    if let eventId = savedEventId, !eventId.isEmpty {
                        // Verify this matches the prompt that was being journaled
                        if eventId == currentPromptEventId {
                            self.taskEndMonitor.markEventAsJournaled(eventId: eventId)
                            // Cancel notification for this event
                            self.notificationManager.cancelJournalPromptNotification(eventId: eventId)
                            print("✅ Journal entry saved and event \(eventId) marked as journaled")
                        } else {
                            print("⚠️ Warning: Saved eventId (\(eventId)) doesn't match prompt eventId (\(currentPromptEventId ?? "nil")) - marking anyway")
                            // Still mark it as journaled to prevent duplicate prompts
                            self.taskEndMonitor.markEventAsJournaled(eventId: eventId)
                            self.notificationManager.cancelJournalPromptNotification(eventId: eventId)
                        }
                    } else {
                        print("⚠️ Warning: Journal entry saved without eventId - cannot mark as journaled")
                    }
                    
                    // Add to local entries
                    self.journalEntries.insert(entry, at: 0)
                    
                    if completionStatus == .completed {
                        self.queueScheduledProofCapture(
                            taskTitle: taskTitle,
                            eventId: savedEventId,
                            completedAt: actualEndTime ?? Date()
                        )
                    } else {
                        // Clear current prompt and show next one
                        // Only clear if this was the prompt we were journaling
                        if let promptEventId = currentPromptEventId,
                           let savedId = savedEventId,
                           promptEventId == savedId {
                            self.pendingJournalPrompt = nil
                            self.showNextPendingPrompt()
                        } else if savedEventId == nil || savedEventId?.isEmpty == true {
                            // If no eventId, just clear and show next (shouldn't happen but handle gracefully)
                            self.pendingJournalPrompt = nil
                            self.showNextPendingPrompt()
                        } else {
                            // EventId doesn't match - this shouldn't happen, but don't clear to be safe
                            print("⚠️ Warning: Not clearing prompt - saved eventId (\(savedEventId ?? "nil")) doesn't match prompt eventId (\(currentPromptEventId ?? "nil"))")
                        }
                    }
                    
                    // Post notification to trigger AI analysis (SmartSchedulingView will listen)
                    NotificationCenter.default.post(name: NSNotification.Name("JournalEntrySaved"), object: nil)
                }
            }
        }
    }
    
    func updateJournalEntry(_ entry: JournalEntry) {
        guard let entryId = entry.id else {
            errorMessage = "Entry ID missing"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        firebaseManager.updateJournalEntry(entry) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "Error updating journal entry: \(error.localizedDescription)"
                    print("Error updating journal entry: \(error.localizedDescription)")
                    return
                }
                
                // Update local entry
                if let index = self.journalEntries.firstIndex(where: { $0.id == entryId }) {
                    self.journalEntries[index] = entry
                }
            }
        }
    }
    
    func deleteJournalEntry(_ entryId: String) {
        isLoading = true
        errorMessage = nil
        
        firebaseManager.deleteJournalEntry(entryId) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "Error deleting journal entry: \(error.localizedDescription)"
                    print("Error deleting journal entry: \(error.localizedDescription)")
                    return
                }
                
                // Remove from local entries
                self.journalEntries.removeAll { $0.id == entryId }
            }
        }
    }
    
    func skipJournalPrompt() {
        // Dismiss sheet FIRST to avoid black flash (Bug 1 fix)
        showingJournalPrompt = false
        // Permanently suppress future auto-prompts (Bug 3 fix)
        autoShowPrompts = false

        if let event = pendingJournalPrompt {
            taskEndMonitor.markEventAsJournaled(eventId: event.eventId)
            // Cancel notification for this event
            notificationManager.cancelJournalPromptNotification(eventId: event.eventId)
        }
        pendingJournalPrompt = nil
        // DON'T call showNextPendingPrompt() - user has opted out permanently
    }

    func completeScheduledProofCaptureFlow() {
        guard awaitingScheduledProofCaptureResolution else { return }
        awaitingScheduledProofCaptureResolution = false
        showingTaskProofCapture = false
        pendingTaskProofCapture = nil
        showNextPendingPrompt()
    }
    
    // Method to show prompt for a specific event (used when notification is tapped)
    func showPromptForEvent(eventId: String) {
        guard !eventId.isEmpty else { return }
        if showingTaskProofCapture {
            if let monitorEvent = taskEndMonitor.pendingJournalEvents.first(where: { $0.eventId == eventId }) {
                enqueueEventIfNeeded(monitorEvent, prioritize: true)
            }
            return
        }

        // Check if it's the current prompt
        if let current = pendingJournalPrompt, current.eventId == eventId {
            showingJournalPrompt = true
            return
        }
        
        // Check if it's in the queue
        if let index = pendingJournalQueue.firstIndex(where: { $0.eventId == eventId }) {
            // Move it to the front of the queue
            let event = pendingJournalQueue.remove(at: index)
            pendingJournalQueue.insert(event, at: 0)
            if !showingJournalPrompt {
                presentQueuedEvent(eventId: eventId)
                return
            }
            return
        }

        if let monitorEvent = taskEndMonitor.pendingJournalEvents.first(where: { $0.eventId == eventId }) {
            enqueueEventIfNeeded(monitorEvent, prioritize: true)
            if !showingJournalPrompt {
                presentQueuedEvent(eventId: eventId)
            }
            return
        }

        // Cold-start/background fallback: resolve event from Firestore.
        firebaseManager.checkJournalEntryExists(eventId: eventId) { [weak self] exists in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard !exists else {
                    print("⚠️ Journal entry already exists for event \(eventId), skipping prompt")
                    return
                }

                self.firebaseManager.fetchScheduledEvent(eventId: eventId) { [weak self] eventData, error in
                    DispatchQueue.main.async {
                        guard let self = self else { return }

                        if let error = error {
                            print("Error fetching scheduled event for journal prompt: \(error.localizedDescription)")
                            return
                        }

                        guard let pendingEvent = self.makePendingEvent(from: eventData, fallbackEventId: eventId) else {
                            print("⚠️ Unable to resolve pending journal event for eventId: \(eventId)")
                            return
                        }

                        self.enqueueEventIfNeeded(pendingEvent, prioritize: true)
                        if !self.showingJournalPrompt {
                            self.presentQueuedEvent(eventId: eventId)
                        }
                    }
                }
            }
        }
    }

    private func hasEventInPromptOrQueue(eventId: String) -> Bool {
        if pendingJournalPrompt?.eventId == eventId {
            return true
        }
        return pendingJournalQueue.contains(where: { $0.eventId == eventId })
    }

    private func enqueueEventIfNeeded(_ event: TaskEndMonitor.PendingJournalEvent, prioritize: Bool = false) {
        guard !hasEventInPromptOrQueue(eventId: event.eventId) else { return }
        if prioritize {
            pendingJournalQueue.insert(event, at: 0)
        } else {
            pendingJournalQueue.append(event)
        }
    }

    private func presentQueuedEvent(eventId: String) {
        guard let index = pendingJournalQueue.firstIndex(where: { $0.eventId == eventId }) else { return }
        let event = pendingJournalQueue.remove(at: index)
        pendingJournalPrompt = event
        showingJournalPrompt = true
    }

    private func makePendingEvent(from scheduledEventData: [String: Any]?, fallbackEventId: String) -> TaskEndMonitor.PendingJournalEvent? {
        guard let scheduledEventData = scheduledEventData else { return nil }

        let resolvedEventId: String
        if let storedEventId = scheduledEventData["eventId"] as? String, !storedEventId.isEmpty {
            resolvedEventId = storedEventId
        } else {
            resolvedEventId = fallbackEventId
        }
        guard let taskTitle = scheduledEventData["taskTitle"] as? String,
              let scheduledStartTime = dateValue(from: scheduledEventData["startTime"]),
              let scheduledEndTime = dateValue(from: scheduledEventData["endTime"]) else {
            return nil
        }

        let tasks = scheduledEventData["tasks"] as? [String] ?? [taskTitle]
        let dayOfWeek = dayOfWeekString(from: scheduledStartTime)

        return TaskEndMonitor.PendingJournalEvent(
            eventId: resolvedEventId,
            taskTitle: taskTitle,
            tasks: tasks,
            scheduledStartTime: scheduledStartTime,
            scheduledEndTime: scheduledEndTime,
            dayOfWeek: dayOfWeek
        )
    }

    private func dateValue(from rawValue: Any?) -> Date? {
        if let timestamp = rawValue as? Timestamp {
            return timestamp.dateValue()
        }
        if let date = rawValue as? Date {
            return date
        }
        return nil
    }

    private func dayOfWeekString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date).lowercased()
    }

    private func queueScheduledProofCapture(taskTitle: String, eventId: String?, completedAt: Date) {
        pendingTaskProofCapture = TaskProofCaptureContext(
            taskTitle: taskTitle,
            sourceType: .scheduled,
            scheduledEventId: eventId,
            localTaskId: nil,
            sharedTaskId: nil,
            completedAt: completedAt
        )

        awaitingScheduledProofCaptureResolution = true
        showingJournalPrompt = false
        pendingJournalPrompt = nil
        showingTaskProofCapture = true
    }
    
    // Helper to trigger AI analysis - will be called from integration
    func triggerJournalAnalysis(schedulingViewModel: SchedulingAssistantViewModel) {
        schedulingViewModel.analyzeJournalEntriesBatch()
    }
    
    // Format journal insights using LLM
    private func formatJournalInsights(
        whatDid: String,
        howWent: String?,
        learned: String?,
        distractions: String?,
        completion: @escaping (String, String?, String?, String?) -> Void
    ) {
        // Build prompt for formatting
        var prompt = """
        You are a helpful assistant that formats journal entries to be clear, concise, and well-written.
        
        Format the following journal entry sections. Keep the user's voice and meaning, but improve:
        - Grammar and spelling
        - Clarity and flow
        - Consistency in tone
        
        Return ONLY a JSON object with these exact keys: "whatDid", "howWent", "learned", "distractions".
        Use null for empty/optional fields.
        
        User's raw input:
        - What did: \(whatDid)
        """
        
        if let howWent = howWent, !howWent.isEmpty {
            prompt += "\n- How it went: \(howWent)"
        }
        if let learned = learned, !learned.isEmpty {
            prompt += "\n- What learned: \(learned)"
        }
        if let distractions = distractions, !distractions.isEmpty {
            prompt += "\n- Distractions: \(distractions)"
        }
        
        prompt += "\n\nReturn the formatted JSON only, no other text."
        
        Task {
            do {
                let vertex = VertexAI.vertexAI()
                let model = vertex.generativeModel(modelName: "gemini-2.5-flash")
                
                let userMessage = ModelContent(role: "user", parts: [TextPart(prompt)])
                let response = try await model.generateContent([userMessage])
                
                guard let text = response.text else {
                    // Fallback to original text if LLM fails
                    DispatchQueue.main.async {
                        completion(
                            whatDid.trimmingCharacters(in: .whitespacesAndNewlines),
                            howWent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? howWent?.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                            learned?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? learned?.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                            distractions?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? distractions?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
                        )
                    }
                    return
                }
                
                // Parse JSON response
                if let jsonData = extractJSONFromResponse(text).data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    let formattedWhatDid = json["whatDid"] as? String ?? whatDid.trimmingCharacters(in: .whitespacesAndNewlines)
                    let formattedHowWent = json["howWent"] as? String
                    let formattedLearned = json["learned"] as? String
                    let formattedDistractions = json["distractions"] as? String
                    
                    DispatchQueue.main.async {
                        completion(
                            formattedWhatDid,
                            formattedHowWent?.isEmpty == false ? formattedHowWent : nil,
                            formattedLearned?.isEmpty == false ? formattedLearned : nil,
                            formattedDistractions?.isEmpty == false ? formattedDistractions : nil
                        )
                    }
                } else {
                    // Fallback to original text if parsing fails
                    DispatchQueue.main.async {
                        completion(
                            whatDid.trimmingCharacters(in: .whitespacesAndNewlines),
                            howWent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? howWent?.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                            learned?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? learned?.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                            distractions?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? distractions?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
                        )
                    }
                }
            } catch {
                print("Error formatting journal insights: \(error.localizedDescription)")
                // Fallback to original text on error
                DispatchQueue.main.async {
                    completion(
                        whatDid.trimmingCharacters(in: .whitespacesAndNewlines),
                        howWent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? howWent?.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                        learned?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? learned?.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                        distractions?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? distractions?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
                    )
                }
            }
        }
    }
    
    // Helper to extract JSON from markdown code blocks
    private func extractJSONFromResponse(_ text: String) -> String {
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
        }
        
        // Fallback: simple string replacement if regex fails
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
            if cleaned.hasPrefix("json") {
                cleaned = String(cleaned.dropFirst(4))
            }
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

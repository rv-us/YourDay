//
//  TaskEndMonitor.swift
//  YourDay
//
//  Monitors scheduled tasks and triggers journal prompts when they end
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
class TaskEndMonitor: ObservableObject {
    static let shared = TaskEndMonitor()
    
    @Published var pendingJournalEvents: [PendingJournalEvent] = []
    
    private let firebaseManager = FirebaseManager.shared
    private var timer: Timer?
    /// Events the user extended ("still working"); suppress prompts until this time.
    private var deferredPromptUntil: [String: Date] = [:]
    
    private init() {
        startMonitoring()
    }
    
    struct PendingJournalEvent {
        let eventId: String
        let taskTitle: String
        let tasks: [String]
        let scheduledStartTime: Date
        let scheduledEndTime: Date
        let dayOfWeek: String
    }
    
    func startMonitoring() {
        if timer != nil { return }

        // Check every minute for ended tasks
        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkForEndedTasks()
            }
        }
        
        // Also check immediately
        Task {
            await checkForEndedTasks()
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    func checkForEndedTasks() async {
        guard Auth.auth().currentUser?.uid != nil else { return }
        
        // Fetch all scheduled events
        await withCheckedContinuation { continuation in
            firebaseManager.fetchScheduledEvents { [weak self] events, error in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                if let error = error {
                    print("Error fetching scheduled events: \(error.localizedDescription)")
                    continuation.resume()
                    return
                }
                
                guard let events = events else {
                    continuation.resume()
                    return
                }
                
                let calendar = Calendar.current
                let now = Date()
                let todayStart = calendar.startOfDay(for: now)
                guard let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) else {
                    continuation.resume()
                    return
                }

                var stillActiveEventIds = Set<String>()
                for eventData in events {
                    if let eventId = eventData["eventId"] as? String,
                       let endTimestamp = eventData["endTime"] as? Timestamp,
                       endTimestamp.dateValue() > now {
                        stillActiveEventIds.insert(eventId)
                    }
                }
                if !stillActiveEventIds.isEmpty {
                    self.pendingJournalEvents.removeAll { stillActiveEventIds.contains($0.eventId) }
                }

                var candidates: [PendingJournalEvent] = []
                for eventData in events {
                    guard let eventId = eventData["eventId"] as? String,
                          let taskTitle = eventData["taskTitle"] as? String,
                          let tasks = eventData["tasks"] as? [String],
                          let startTimestamp = eventData["startTime"] as? Timestamp,
                          let endTimestamp = eventData["endTime"] as? Timestamp else {
                        continue
                    }

                    // User already dismissed the journal prompt for this event
                    // (skipped or rescheduled). Don't re-surface it.
                    if let promptSkipped = eventData["promptSkipped"] as? Bool, promptSkipped {
                        continue
                    }

                    let scheduledStartTime = startTimestamp.dateValue()
                    let scheduledEndTime = endTimestamp.dateValue()

                    if let deferredUntil = self.deferredPromptUntil[eventId] {
                        if deferredUntil > now {
                            continue
                        }
                        self.deferredPromptUntil.removeValue(forKey: eventId)
                    }

                    // Only re-surface tasks scheduled for today whose end time
                    // has passed — ignore yesterday's and future events.
                    guard scheduledEndTime <= now,
                          scheduledStartTime >= todayStart,
                          scheduledStartTime < tomorrowStart else {
                        continue
                    }

                    if self.pendingJournalEvents.contains(where: { $0.eventId == eventId }) {
                        continue
                    }
                    if JournalViewModel.shared.isEventInActiveJournalUI(eventId: eventId) {
                        continue
                    }

                    let formatter = DateFormatter()
                    formatter.dateFormat = "EEEE"
                    let dayOfWeek = formatter.string(from: scheduledStartTime).lowercased()

                    candidates.append(PendingJournalEvent(
                        eventId: eventId,
                        taskTitle: taskTitle,
                        tasks: tasks,
                        scheduledStartTime: scheduledStartTime,
                        scheduledEndTime: scheduledEndTime,
                        dayOfWeek: dayOfWeek
                    ))
                }

                guard !candidates.isEmpty else {
                    continuation.resume()
                    return
                }

                // Resolve journal-entry-exists checks, then append in
                // chronological order (earliest scheduled start first).
                let group = DispatchGroup()
                var newEvents: [PendingJournalEvent] = []
                for candidate in candidates {
                    group.enter()
                    self.checkIfJournalEntryExists(eventId: candidate.eventId) { exists in
                        DispatchQueue.main.async {
                            if !exists {
                                newEvents.append(candidate)
                            }
                            group.leave()
                        }
                    }
                }

                group.notify(queue: .main) {
                    let sorted = newEvents.sorted { $0.scheduledStartTime < $1.scheduledStartTime }
                    for event in sorted {
                        if !self.pendingJournalEvents.contains(where: { $0.eventId == event.eventId }) {
                            self.pendingJournalEvents.append(event)
                        }
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    private func checkIfJournalEntryExists(eventId: String, completion: @escaping (Bool) -> Void) {
        firebaseManager.checkJournalEntryExists(eventId: eventId, completion: completion)
    }
    
    func markEventAsJournaled(eventId: String) {
        pendingJournalEvents.removeAll { $0.eventId == eventId }
        deferredPromptUntil.removeValue(forKey: eventId)
        // Cancel notification for this event
        NotificationManager.shared.cancelJournalPromptNotification(eventId: eventId)
    }

    /// User chose "still working" and extended the session. Hide prompts and in-app
    /// queue entries until `newEndTime`, then allow `checkForEndedTasks` to surface again.
    func deferJournalPrompt(eventId: String, until newEndTime: Date) {
        guard !eventId.isEmpty else { return }
        deferredPromptUntil[eventId] = newEndTime
        pendingJournalEvents.removeAll { $0.eventId == eventId }
    }

    func isJournalPromptDeferred(eventId: String) -> Bool {
        guard let deferredUntil = deferredPromptUntil[eventId] else { return false }
        return deferredUntil > Date()
    }
    
    // Force check on app activation
    func forceCheck() {
        Task {
            await checkForEndedTasks()
        }
    }
}

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
                
                let now = Date()
                let checkWindow: TimeInterval = 24 * 60 * 60 // 24 hours (expanded from 5 minutes to catch missed events)
                
                for eventData in events {
                    guard let eventId = eventData["eventId"] as? String,
                          let taskTitle = eventData["taskTitle"] as? String,
                          let tasks = eventData["tasks"] as? [String],
                          let startTimestamp = eventData["startTime"] as? Timestamp,
                          let endTimestamp = eventData["endTime"] as? Timestamp else {
                        continue
                    }
                    
                    let scheduledStartTime = startTimestamp.dateValue()
                    let scheduledEndTime = endTimestamp.dateValue()
                    
                    // Check if event ended within the expanded window (last 24 hours)
                    let timeSinceEnd = now.timeIntervalSince(scheduledEndTime)
                    if timeSinceEnd >= 0 && timeSinceEnd <= checkWindow {
                        // Check if this event is already in pending list
                        if !self.pendingJournalEvents.contains(where: { $0.eventId == eventId }) {
                            // Check if we already have a journal entry for this event
                            self.checkIfJournalEntryExists(eventId: eventId) { exists in
                                if !exists {
                                    let formatter = DateFormatter()
                                    formatter.dateFormat = "EEEE"
                                    let dayOfWeek = formatter.string(from: scheduledStartTime).lowercased()
                                    
                                    let pendingEvent = PendingJournalEvent(
                                        eventId: eventId,
                                        taskTitle: taskTitle,
                                        tasks: tasks,
                                        scheduledStartTime: scheduledStartTime,
                                        scheduledEndTime: scheduledEndTime,
                                        dayOfWeek: dayOfWeek
                                    )
                                    DispatchQueue.main.async {
                                        if !self.pendingJournalEvents.contains(where: { $0.eventId == eventId }) {
                                            self.pendingJournalEvents.append(pendingEvent)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                continuation.resume()
            }
        }
    }
    
    private func checkIfJournalEntryExists(eventId: String, completion: @escaping (Bool) -> Void) {
        firebaseManager.checkJournalEntryExists(eventId: eventId, completion: completion)
    }
    
    func markEventAsJournaled(eventId: String) {
        pendingJournalEvents.removeAll { $0.eventId == eventId }
        // Cancel notification for this event
        NotificationManager.shared.cancelJournalPromptNotification(eventId: eventId)
    }
    
    // Force check on app activation
    func forceCheck() {
        Task {
            await checkForEndedTasks()
        }
    }
}

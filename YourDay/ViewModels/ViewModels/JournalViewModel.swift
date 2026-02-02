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

@MainActor
class JournalViewModel: ObservableObject {
    static let shared = JournalViewModel()
    
    @Published var journalEntries: [JournalEntry] = []
    @Published var pendingJournalPrompt: TaskEndMonitor.PendingJournalEvent?
    @Published var showingJournalPrompt = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Queue for pending journal events
    private var pendingJournalQueue: [TaskEndMonitor.PendingJournalEvent] = []
    
    var pendingCount: Int {
        pendingJournalQueue.count + (pendingJournalPrompt != nil ? 1 : 0)
    }
    
    private let firebaseManager = FirebaseManager.shared
    private let taskEndMonitor = TaskEndMonitor.shared
    private let notificationManager = NotificationManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Observe pending journal events from TaskEndMonitor
        taskEndMonitor.$pendingJournalEvents
            .sink { [weak self] events in
                guard let self = self else { return }
                // Add all new events to queue (avoid duplicates)
                let existingEventIds = Set(self.pendingJournalQueue.map { $0.eventId })
                let newEvents = events.filter { !existingEventIds.contains($0.eventId) }
                
                // Add new events to queue
                self.pendingJournalQueue.append(contentsOf: newEvents)
                
                // Schedule notifications for new events
                for event in newEvents {
                    self.notificationManager.scheduleJournalPromptNotification(
                        eventId: event.eventId,
                        taskTitle: event.taskTitle,
                        scheduledEndTime: event.scheduledEndTime
                    )
                }
                
                // Show next prompt if not already showing one
                if !self.showingJournalPrompt {
                    self.showNextPendingPrompt()
                }
            }
            .store(in: &cancellables)
    }
    
    private func showNextPendingPrompt() {
        // Remove the next event from queue and show it
        guard !pendingJournalQueue.isEmpty else {
            pendingJournalPrompt = nil
            showingJournalPrompt = false
            return
        }
        
        let nextEvent = pendingJournalQueue.removeFirst()
        pendingJournalPrompt = nextEvent
        showingJournalPrompt = true
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
        
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let dayOfWeek = formatter.string(from: scheduledStartTime).lowercased()
        
        let entry = JournalEntry(
            userId: userId,
            eventId: eventId,
            taskTitle: taskTitle,
            scheduledStartTime: scheduledStartTime,
            scheduledEndTime: scheduledEndTime,
            actualStartTime: actualStartTime,
            actualEndTime: actualEndTime,
            whatDid: whatDid.trimmingCharacters(in: .whitespacesAndNewlines),
            howWent: howWent?.trimmingCharacters(in: .whitespacesAndNewlines),
            learned: learned?.trimmingCharacters(in: .whitespacesAndNewlines),
            distractions: distractions?.trimmingCharacters(in: .whitespacesAndNewlines),
            completionStatus: completionStatus,
            dayOfWeek: dayOfWeek
        )
        
        firebaseManager.saveJournalEntry(entry) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "Error saving journal entry: \(error.localizedDescription)"
                    print("Error saving journal entry: \(error.localizedDescription)")
                    return
                }
                
                // Mark event as journaled
                if let eventId = eventId {
                    self.taskEndMonitor.markEventAsJournaled(eventId: eventId)
                    // Cancel notification for this event
                    self.notificationManager.cancelJournalPromptNotification(eventId: eventId)
                }
                
                // Add to local entries
                self.journalEntries.insert(entry, at: 0)
                
                // Clear current prompt and show next one
                self.pendingJournalPrompt = nil
                self.showNextPendingPrompt()
                
                // Post notification to trigger AI analysis (SmartSchedulingView will listen)
                NotificationCenter.default.post(name: NSNotification.Name("JournalEntrySaved"), object: nil)
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
        if let event = pendingJournalPrompt {
            taskEndMonitor.markEventAsJournaled(eventId: event.eventId)
            // Cancel notification for this event
            notificationManager.cancelJournalPromptNotification(eventId: event.eventId)
        }
        pendingJournalPrompt = nil
        // Show next prompt from queue
        showNextPendingPrompt()
    }
    
    // Method to show prompt for a specific event (used when notification is tapped)
    func showPromptForEvent(eventId: String) {
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
            // Show it if not already showing another
            if !showingJournalPrompt {
                showNextPendingPrompt()
            }
        }
    }
    
    // Helper to trigger AI analysis - will be called from integration
    func triggerJournalAnalysis(schedulingViewModel: SchedulingAssistantViewModel) {
        schedulingViewModel.analyzeJournalEntriesBatch()
    }
}


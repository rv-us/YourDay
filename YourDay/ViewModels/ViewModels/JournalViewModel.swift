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
    @Published var journalEntries: [JournalEntry] = []
    @Published var pendingJournalPrompt: TaskEndMonitor.PendingJournalEvent?
    @Published var showingJournalPrompt = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let firebaseManager = FirebaseManager.shared
    private let taskEndMonitor = TaskEndMonitor.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Observe pending journal events from TaskEndMonitor
        taskEndMonitor.$pendingJournalEvents
            .sink { [weak self] events in
                guard let self = self else { return }
                // Show prompt for the most recent event
                if let latestEvent = events.first, !self.showingJournalPrompt {
                    self.pendingJournalPrompt = latestEvent
                    self.showingJournalPrompt = true
                }
            }
            .store(in: &cancellables)
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
                }
                
                // Add to local entries
                self.journalEntries.insert(entry, at: 0)
                
                // Clear prompt
                self.pendingJournalPrompt = nil
                self.showingJournalPrompt = false
                
                // Note: AI analysis is triggered from the view layer after journal entry is saved
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
        }
        pendingJournalPrompt = nil
        showingJournalPrompt = false
    }
    
    // Helper to trigger AI analysis - will be called from integration
    func triggerJournalAnalysis(schedulingViewModel: SchedulingAssistantViewModel) {
        schedulingViewModel.analyzeJournalEntriesBatch()
    }
}


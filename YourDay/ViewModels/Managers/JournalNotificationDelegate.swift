//
//  JournalNotificationDelegate.swift
//  YourDay
//
//  Handles notification taps for journal prompts
//

import Foundation
import UserNotifications

class JournalNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = JournalNotificationDelegate()
    
    private var journalViewModel: JournalViewModel?
    private var bufferedEventIds: [String] = []
    
    private override init() {
        super.init()
    }
    
    func setJournalViewModel(_ viewModel: JournalViewModel) {
        self.journalViewModel = viewModel
        
        guard !bufferedEventIds.isEmpty else { return }
        let pendingEventIds = bufferedEventIds
        bufferedEventIds.removeAll()
        Task { @MainActor in
            for eventId in pendingEventIds {
                viewModel.showPromptForEvent(eventId: eventId)
            }
        }
    }
    
    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        // Check if this is a journal prompt notification
        if let type = userInfo["type"] as? String, type == "journalPrompt",
           let eventId = userInfo["eventId"] as? String {
            if let journalViewModel = journalViewModel {
                Task { @MainActor in
                    journalViewModel.showPromptForEvent(eventId: eventId)
                }
            } else if !bufferedEventIds.contains(eventId) {
                bufferedEventIds.append(eventId)
            }

            // Post notification to show journal prompt
            NotificationCenter.default.post(
                name: NSNotification.Name("ShowJournalPrompt"),
                object: nil,
                userInfo: ["eventId": eventId]
            )
        }
        
        completionHandler()
    }
}

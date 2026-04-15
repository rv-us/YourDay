//
//  JournalNotificationDelegate.swift
//  YourDay
//
//  Handles notification taps for journal prompts and remote chat pushes.
//

import Foundation
import UserNotifications

class JournalNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = JournalNotificationDelegate()

    private var journalViewModel: JournalViewModel?
    private var bufferedEventIds: [String] = []

    /// The senderId of the DM conversation the user is currently viewing.
    /// Set this to the friend's userId when a chat view opens; nil when it closes.
    var activeChatFriendId: String?

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

    // MARK: - Foreground presentation

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo

        // Suppress chat banner when the user already has that conversation open
        if let type = userInfo["type"] as? String, type == "chatMessage",
           let senderId = userInfo["senderId"] as? String,
           senderId == activeChatFriendId {
            completionHandler([])
            return
        }

        completionHandler([.banner, .sound, .badge])
    }

    // MARK: - Tap handling

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        if let type = userInfo["type"] as? String {
            switch type {
            case "journalPrompt":
                if let eventId = userInfo["eventId"] as? String {
                    if let journalViewModel {
                        Task { @MainActor in
                            journalViewModel.showPromptForEvent(eventId: eventId)
                        }
                    } else if !bufferedEventIds.contains(eventId) {
                        bufferedEventIds.append(eventId)
                    }
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ShowJournalPrompt"),
                        object: nil,
                        userInfo: ["eventId": eventId]
                    )
                }

            case "chatMessage":
                if let senderId = userInfo["senderId"] as? String {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("OpenChatWithFriend"),
                        object: nil,
                        userInfo: ["senderId": senderId]
                    )
                }

            default:
                break
            }
        }

        completionHandler()
    }
}

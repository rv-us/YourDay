import Foundation
import UserNotifications
import SwiftData

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    private init() {}
    
    // MARK: - Task-Based Reminders
    
    func generateTaskBasedNotification(context: SwiftData.ModelContext, type: NotificationType) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        
        switch type {
        case .morning:
            let (title, body) = generateMorningTaskMessage(context: context)
            content.title = title
            content.body = body
        case .night:
            let (title, body) = generateNightTaskMessage(context: context)
            content.title = title
            content.body = body
        case .extra:
            let (title, body) = generateExtraTaskMessage(context: context)
            content.title = title
            content.body = body
        }
        
        content.sound = .default
        return content
    }
    
    private func generateMorningTaskMessage(context: SwiftData.ModelContext) -> (String, String) {
        let incompleteTasks = getIncompleteTasks(context)
        let totalTasks = getTotalTasks(context)
        
        if incompleteTasks.isEmpty {
            return (
                "Good Morning! 🌅",
                "You have no tasks for today. Time to set some goals and make today productive!"
            )
        }
        
        let progressPercentage = calculateProgressPercentage(completed: totalTasks - incompleteTasks.count, total: totalTasks)
        
        // Different messages based on progress and task count
        if incompleteTasks.count <= 2 {
            return (
                "Almost There! 🎯",
                "You only have \(incompleteTasks.count) task\(incompleteTasks.count == 1 ? "" : "s") left. Let's finish strong!"
            )
        } else if progressPercentage >= 0.7 {
            return (
                "Great Progress! ⚡",
                "You're \(Int(progressPercentage * 100))% done! \(incompleteTasks.count) more task\(incompleteTasks.count == 1 ? "" : "s") to go."
            )
        } else if incompleteTasks.count <= 5 {
            let randomTask = incompleteTasks.randomElement()
            return (
                "Ready to Conquer! 💪",
                "You have \(incompleteTasks.count) tasks today. Start with '\(randomTask?.title ?? "your first task")'!"
            )
        } else {
            let urgentTasks = incompleteTasks.filter { Calendar.current.isDateInToday($0.dueDate) }
            if !urgentTasks.isEmpty {
                return (
                    "Priority Tasks Await! ⏰",
                    "You have \(urgentTasks.count) task\(urgentTasks.count == 1 ? "" : "s") due today. Focus on what matters most!"
                )
            } else {
                return (
                    "Plan Your Day! 📋",
                    "You have \(incompleteTasks.count) tasks to tackle. Break them down and take it one step at a time."
                )
            }
        }
    }
    
    private func generateNightTaskMessage(context: SwiftData.ModelContext) -> (String, String) {
        let incompleteTasks = getIncompleteTasks(context)
        let completedTasks = getCompletedTasks(context)
        let totalTasks = getTotalTasks(context)
        
        if totalTasks == 0 {
            return (
                "No Tasks Today 📝",
                "You didn't have any tasks scheduled. Ready to plan tomorrow?"
            )
        }
        
        let progressPercentage = calculateProgressPercentage(completed: completedTasks.count, total: totalTasks)
        
        if incompleteTasks.isEmpty {
            return (
                "Perfect Day! 🎉",
                "You completed all \(completedTasks.count) task\(completedTasks.count == 1 ? "" : "s")! Amazing work!"
            )
        } else if progressPercentage >= 0.8 {
            return (
                "Excellent Progress! 🌟",
                "You completed \(completedTasks.count) out of \(totalTasks) tasks (\(Int(progressPercentage * 100))%). Almost perfect!"
            )
        } else if progressPercentage >= 0.5 {
            return (
                "Good Effort! 👍",
                "You completed \(completedTasks.count) out of \(totalTasks) tasks. \(incompleteTasks.count) more to go tomorrow!"
            )
        } else {
            let overdueTasks = incompleteTasks.filter { $0.dueDate < Date() }
            if !overdueTasks.isEmpty {
                return (
                    "Some Tasks Overdue ⚠️",
                    "You have \(overdueTasks.count) overdue task\(overdueTasks.count == 1 ? "" : "s"). Consider rescheduling or prioritizing them."
                )
            } else {
                return (
                    "Tomorrow's Another Day 🌙",
                    "You completed \(completedTasks.count) out of \(totalTasks) tasks. Don't worry, you can catch up tomorrow!"
                )
            }
        }
    }
    
    private func generateExtraTaskMessage(context: SwiftData.ModelContext) -> (String, String) {
        let incompleteTasks = getIncompleteTasks(context)
        let completedTasks = getCompletedTasks(context)
        let totalTasks = getTotalTasks(context)
        
        if incompleteTasks.isEmpty {
            return (
                "All Caught Up! ✅",
                "Great job! You've completed all your tasks for today."
            )
        }
        
        let progressPercentage = calculateProgressPercentage(completed: completedTasks.count, total: totalTasks)
        let randomTask = incompleteTasks.randomElement()
        
        // Different messages based on time of day and progress
        let hour = Calendar.current.component(.hour, from: Date())
        
        if hour < 12 {
            return (
                "Morning Check-in ☀️",
                "You have \(incompleteTasks.count) task\(incompleteTasks.count == 1 ? "" : "s") left. How about tackling '\(randomTask?.title ?? "your next task")'?"
            )
        } else if hour < 17 {
            return (
                "Afternoon Boost! ☕",
                "You're \(Int(progressPercentage * 100))% done! Keep the momentum going with '\(randomTask?.title ?? "your next task")'."
            )
        } else {
            return (
                "Evening Wrap-up 🌆",
                "\(incompleteTasks.count) task\(incompleteTasks.count == 1 ? "" : "s") remaining. Finish strong with '\(randomTask?.title ?? "your next task")'!"
            )
        }
    }
    
    // MARK: - Helper Methods
    
    private func getIncompleteTasks(_ context: SwiftData.ModelContext) -> [TodoItem] {
        let descriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate<TodoItem> { !$0.isDone }
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            print("Error fetching incomplete tasks: \(error)")
            return []
        }
    }
    
    private func getCompletedTasks(_ context: SwiftData.ModelContext) -> [TodoItem] {
        let descriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate<TodoItem> { $0.isDone }
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            print("Error fetching completed tasks: \(error)")
            return []
        }
    }
    
    private func getTotalTasks(_ context: SwiftData.ModelContext) -> Int {
        let descriptor = FetchDescriptor<TodoItem>()
        do {
            return try context.fetch(descriptor).count
        } catch {
            print("Error fetching total tasks: \(error)")
            return 0
        }
    }
    
    private func calculateProgressPercentage(completed: Int, total: Int) -> Double {
        guard total > 0 else { return 0.0 }
        return Double(completed) / Double(total)
    }
    
    // MARK: - Journal Prompt Notifications
    
    func scheduleJournalPromptNotification(eventId: String, taskTitle: String, scheduledEndTime: Date) {
        // Check if notifications are enabled
        let notificationsEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        guard notificationsEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Task Check-In"
        content.body = "Did you complete '\(taskTitle)'? Tap to journal or reschedule."
        content.sound = .default
        content.userInfo = [
            "type": "journalPrompt",
            "eventId": eventId
        ]
        
        let identifier = "journalPrompt_\(eventId)"
        let center = UNUserNotificationCenter.current()

        // Ensure we keep one notification per event id.
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])

        let trigger: UNNotificationTrigger?
        if scheduledEndTime > Date() {
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: scheduledEndTime)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        } else {
            // If the end time has already passed, prompt immediately.
            trigger = nil
        }

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        center.add(request) { error in
            if let error = error {
                print("Error scheduling journal prompt notification: \(error.localizedDescription)")
            } else {
                print("✅ Scheduled journal prompt notification for event: \(eventId)")
            }
        }
    }
    
    func cancelJournalPromptNotification(eventId: String) {
        let identifier = "journalPrompt_\(eventId)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func cancelAllJournalPromptNotifications() {
        let center = UNUserNotificationCenter.current()

        center.getPendingNotificationRequests { requests in
            let identifiers = requests
                .map(\.identifier)
                .filter { $0.hasPrefix("journalPrompt_") }
            guard !identifiers.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }

        center.getDeliveredNotifications { notifications in
            let identifiers = notifications
                .map { $0.request.identifier }
                .filter { $0.hasPrefix("journalPrompt_") }
            guard !identifiers.isEmpty else { return }
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    // MARK: - Chat Message Notifications

    /// Schedules a local notification for an incoming chat message. Respects the app's notificationsEnabled setting.
    func scheduleChatMessageNotification(senderName: String, messagePreview: String, senderId: String) {
        let notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "New message from \(senderName)"
        let body = messagePreview.isEmpty ? "Tap to open chat." : messagePreview
        content.body = body.count > 120 ? String(body.prefix(117)) + "..." : body
        content.sound = .default
        content.userInfo = [
            "type": "chatMessage",
            "senderId": senderId
        ]

        let identifier = "chatMessage_\(senderId)_\(UUID().uuidString)"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling chat notification: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Notification Types

enum NotificationType {
    case morning
    case night
    case extra
} 

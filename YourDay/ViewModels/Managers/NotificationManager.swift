import Foundation
import UserNotifications
import SwiftData

final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    static let morningReminderKey = "morningReminderTime"
    static let nightReminderKey = "nightReminderTime"
    static let notificationsEnabledKey = "notificationsEnabled"
    static let extraNotificationsKey = "extraNotificationCount"
    static let locationRemindersEnabledKey = "locationRemindersEnabled"
    static let scheduledReminderIDs: [String] = ["morningReminder", "nightReminder"] + (1...10).map { "extraReminder\($0)" }

    private var journalViewModel: JournalViewModel?
    private var bufferedEventIds: [String] = []

    /// The senderId of the DM conversation the user is currently viewing.
    /// Set this to the friend's userId when a chat view opens; nil when it closes.
    var activeChatFriendId: String?

    private override init() {
        super.init()
    }

    func requestPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                print("NotificationManager: Notification auth error - \(error.localizedDescription)")
            } else {
                print("NotificationManager: Notification permission granted = \(granted)")
            }
        }
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

    // MARK: - Daily reminder scheduling

    func rescheduleIfNeeded(context: SwiftData.ModelContext) {
        let notificationsEnabled = UserDefaults.standard.object(forKey: Self.notificationsEnabledKey) as? Bool ?? true
        guard notificationsEnabled else { return }

        let morningTime = UserDefaults.standard.object(forKey: Self.morningReminderKey) as? Date
            ?? Calendar.current.date(from: DateComponents(hour: 9))
            ?? Date()
        let nightTime = UserDefaults.standard.object(forKey: Self.nightReminderKey) as? Date
            ?? Calendar.current.date(from: DateComponents(hour: 21))
            ?? Date()
        let extraNotificationCount = UserDefaults.standard.object(forKey: Self.extraNotificationsKey) as? Int ?? 0

        let calendar = Calendar.current
        let morningHour = calendar.component(.hour, from: morningTime)
        let morningMinute = calendar.component(.minute, from: morningTime)
        let nightHour = calendar.component(.hour, from: nightTime)
        let nightMinute = calendar.component(.minute, from: nightTime)

        scheduleDailyReminders(
            morningHour: morningHour,
            morningMinute: morningMinute,
            nightHour: nightHour,
            nightMinute: nightMinute,
            extraReminders: extraNotificationCount,
            context: context
        )
    }

    func scheduleDailyReminders(
        morningHour: Int,
        morningMinute: Int,
        nightHour: Int,
        nightMinute: Int,
        extraReminders: Int,
        context: SwiftData.ModelContext
    ) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: Self.scheduledReminderIDs)

        let morningContent = generateTaskBasedNotification(context: context, type: .morning)
        let morningTrigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: morningHour, minute: morningMinute),
            repeats: true
        )
        center.add(UNNotificationRequest(identifier: "morningReminder", content: morningContent, trigger: morningTrigger))

        let nightContent = generateTaskBasedNotification(context: context, type: .night)
        let nightTrigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: nightHour, minute: nightMinute),
            repeats: true
        )
        center.add(UNNotificationRequest(identifier: "nightReminder", content: nightContent, trigger: nightTrigger))

        if extraReminders > 0 {
            let startMinutes = morningHour * 60 + morningMinute
            let endMinutes = nightHour * 60 + nightMinute
            guard endMinutes > startMinutes else {
                print("NotificationManager: Invalid time range for extra reminders.")
                return
            }

            let interval = (endMinutes - startMinutes) / (extraReminders + 1)

            for i in 1...extraReminders {
                let scheduledMinutes = startMinutes + i * interval
                let hour = scheduledMinutes / 60
                let minute = scheduledMinutes % 60

                let extraContent = generateTaskBasedNotification(context: context, type: .extra)
                let extraTrigger = UNCalendarNotificationTrigger(
                    dateMatching: DateComponents(hour: hour, minute: minute),
                    repeats: true
                )

                let id = "extraReminder\(i)"
                center.add(UNNotificationRequest(identifier: id, content: extraContent, trigger: extraTrigger))
            }
        }
    }

    // MARK: - Task-based reminder content

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
        switch currentTimeSegment() {
        case .morning:
            return (
                "Morning Check-in ☀️",
                "You have \(incompleteTasks.count) task\(incompleteTasks.count == 1 ? "" : "s") left. How about tackling '\(randomTask?.title ?? "your next task")'?"
            )
        case .afternoon:
            return (
                "Afternoon Boost! ☕",
                "You're \(Int(progressPercentage * 100))% done! Keep the momentum going with '\(randomTask?.title ?? "your next task")'."
            )
        case .evening:
            return (
                "Evening Wrap-up 🌆",
                "\(incompleteTasks.count) task\(incompleteTasks.count == 1 ? "" : "s") remaining. Finish strong with '\(randomTask?.title ?? "your next task")'!"
            )
        case .night:
            return (
                "Night Focus 🌙",
                "\(incompleteTasks.count) task\(incompleteTasks.count == 1 ? "" : "s") still open. A quick push on '\(randomTask?.title ?? "your next task")' can set up tomorrow."
            )
        }
    }

    // MARK: - Journal prompt notifications

    func scheduleJournalPromptNotification(eventId: String, taskTitle: String, scheduledEndTime: Date) {
        let notificationsEnabled = UserDefaults.standard.object(forKey: Self.notificationsEnabledKey) as? Bool ?? true
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

        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])

        let trigger: UNNotificationTrigger?
        if scheduledEndTime > Date() {
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: scheduledEndTime)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        } else {
            trigger = nil
        }

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error = error {
                print("NotificationManager: Error scheduling journal prompt notification - \(error.localizedDescription)")
            } else {
                print("NotificationManager: Scheduled journal prompt notification for event \(eventId)")
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

    // MARK: - Location-based reminders

    func scheduleGeofenceNotification(regionTitle: String, tasks: [String]) {
        let notificationsEnabled = UserDefaults.standard.object(forKey: Self.notificationsEnabledKey) as? Bool ?? true
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "You're near \(regionTitle)"
        let preview = tasks.prefix(3).joined(separator: ", ")
        content.body = tasks.count > 3 ? "\(preview) +\(tasks.count - 3) more" : preview
        content.sound = .default

        let request = UNNotificationRequest(identifier: "geo_\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo

        if let type = userInfo["type"] as? String,
           type == "chatMessage",
           let senderId = userInfo["senderId"] as? String,
           senderId == activeChatFriendId {
            completionHandler([])
            return
        }

        completionHandler([.banner, .sound, .badge])
    }

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

    // MARK: - Helper methods

    private func getIncompleteTasks(_ context: SwiftData.ModelContext) -> [TodoItem] {
        let descriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate<TodoItem> { !$0.isDone }
        )
        do {
            return try context.fetch(descriptor).filter { $0.origin == .today }
        } catch {
            print("NotificationManager: Error fetching incomplete tasks - \(error)")
            return []
        }
    }

    private func getCompletedTasks(_ context: SwiftData.ModelContext) -> [TodoItem] {
        let descriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate<TodoItem> { $0.isDone }
        )
        do {
            return try context.fetch(descriptor).filter { $0.origin == .today }
        } catch {
            print("NotificationManager: Error fetching completed tasks - \(error)")
            return []
        }
    }

    private func getTotalTasks(_ context: SwiftData.ModelContext) -> Int {
        let descriptor = FetchDescriptor<TodoItem>()
        do {
            return try context.fetch(descriptor).filter { $0.origin == .today }.count
        } catch {
            print("NotificationManager: Error fetching total tasks - \(error)")
            return 0
        }
    }

    private func calculateProgressPercentage(completed: Int, total: Int) -> Double {
        guard total > 0 else { return 0.0 }
        return Double(completed) / Double(total)
    }

    private enum TimeSegment {
        case morning
        case afternoon
        case evening
        case night
    }

    private func currentTimeSegment() -> TimeSegment {
        let hour = Calendar.current.component(.hour, from: Date())

        if hour < 8 {
            return .night
        } else if hour < 12 {
            return .morning
        } else if hour < 16 {
            return .afternoon
        } else if hour < 19 {
            return .evening
        } else {
            return .night
        }
    }
}

enum NotificationType {
    case morning
    case night
    case extra
}

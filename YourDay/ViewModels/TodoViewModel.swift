//
//  TodoViewModel.swift
//  YourDay
//
//  Created by Rachit Verma on 4/14/25.
//

import Foundation
import UserNotifications
import SwiftData

class TodoViewModel: ObservableObject {
    @Published var showingNewItemView = false
    @Published var showingDailySummary = false
    
    // Function to reschedule notifications with current task state
    func rescheduleNotificationsIfNeeded(context: SwiftData.ModelContext) {
        // Only reschedule if notifications are enabled
        let notificationsEnabled = UserDefaults.standard.bool(forKey: notificationsEnabledKey)
        guard notificationsEnabled else { return }
        
        // Get current notification settings
        let morningTime = UserDefaults.standard.object(forKey: morningReminderKey) as? Date ?? Calendar.current.date(from: DateComponents(hour: 9)) ?? Date()
        let nightTime = UserDefaults.standard.object(forKey: nightReminderKey) as? Date ?? Calendar.current.date(from: DateComponents(hour: 21)) ?? Date()
        let extraNotificationCount = UserDefaults.standard.object(forKey: extraNotificationsKey) as? Int ?? 0
        
        let calendar = Calendar.current
        let morningHour = calendar.component(.hour, from: morningTime)
        let morningMinute = calendar.component(.minute, from: morningTime)
        let nightHour = calendar.component(.hour, from: nightTime)
        let nightMinute = calendar.component(.minute, from: nightTime)
        
        // Reschedule with current task state
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

        let idsToRemove = ["morningReminder", "nightReminder"] + (1...10).map { "extraReminder\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: idsToRemove)

        // Morning Reminder with task-based content
        let morningContent = NotificationManager.shared.generateTaskBasedNotification(context: context, type: .morning)
        let morningTrigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: morningHour, minute: morningMinute),
            repeats: true
        )
        center.add(UNNotificationRequest(identifier: "morningReminder", content: morningContent, trigger: morningTrigger))

        // Night Reminder with progress-based content
        let nightContent = NotificationManager.shared.generateTaskBasedNotification(context: context, type: .night)
        let nightTrigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: nightHour, minute: nightMinute),
            repeats: true
        )
        center.add(UNNotificationRequest(identifier: "nightReminder", content: nightContent, trigger: nightTrigger))

        // Extra Reminders with task-aware content
        if extraReminders > 0 {
            let startMinutes = morningHour * 60 + morningMinute
            let endMinutes = nightHour * 60 + nightMinute
            guard endMinutes > startMinutes else {
                print("Invalid time range for extra reminders.")
                return
            }

            let interval = (endMinutes - startMinutes) / (extraReminders + 1)

            for i in 1...extraReminders {
                let scheduledMinutes = startMinutes + i * interval
                let hour = scheduledMinutes / 60
                let minute = scheduledMinutes % 60

                let extraContent = NotificationManager.shared.generateTaskBasedNotification(context: context, type: .extra)
                let extraTrigger = UNCalendarNotificationTrigger(
                    dateMatching: DateComponents(hour: hour, minute: minute),
                    repeats: true
                )

                let id = "extraReminder\(i)"
                center.add(UNNotificationRequest(identifier: id, content: extraContent, trigger: extraTrigger))
            }
        }
    }
}

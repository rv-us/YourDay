//
//  TodoViewModel.swift
//  YourDay
//
//  Created by Rachit Verma on 4/14/25.
//

import Foundation
import UserNotifications

class TodoViewModel: ObservableObject {
    @Published var showingNewItemView = false
    @Published var showingSettings = false

    func scheduleDailyReminders(
        morningHour: Int,
        morningMinute: Int,
        nightHour: Int,
        nightMinute: Int,
        extraReminders: Int
    ) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        // Morning Reminder
        let morningContent = UNMutableNotificationContent()
        morningContent.title = "Plan Your Day"
        morningContent.body = "Start your day by creating your to-do list!"

        let morningTrigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: morningHour, minute: morningMinute),
            repeats: true
        )
        center.add(UNNotificationRequest(identifier: "morningReminder", content: morningContent, trigger: morningTrigger))

        // Night Reminder
        let nightContent = UNMutableNotificationContent()
        nightContent.title = "Review Your Day"
        nightContent.body = "Don't forget to check off completed tasks!"

        let nightTrigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: nightHour, minute: nightMinute),
            repeats: true
        )
        center.add(UNNotificationRequest(identifier: "nightReminder", content: nightContent, trigger: nightTrigger))

        // Extra Reminders
        let maxReminders = UserDefaults.standard.integer(forKey: extraNotificationsKey)
        var alreadySent = UserDefaults.standard.integer(forKey: "totalExtraRemindersSentToday")

        if maxReminders > 0 {
            let startMinutes = morningHour * 60 + morningMinute
            let endMinutes = nightHour * 60 + nightMinute
            let interval = (endMinutes - startMinutes) / (maxReminders + 1)

            for i in 1...extraReminders {
                if alreadySent >= maxReminders { break }

                let scheduledMinutes = startMinutes + i * interval
                let hour = scheduledMinutes / 60
                let minute = scheduledMinutes % 60

                let extraContent = UNMutableNotificationContent()
                extraContent.title = "Task Check-In"
                extraContent.body = "Take a moment to update your to-dos."
                extraContent.sound = .default

                let extraTrigger = UNCalendarNotificationTrigger(
                    dateMatching: DateComponents(hour: hour, minute: minute),
                    repeats: true
                )

                let id = "extraReminder\(i)"
                center.add(UNNotificationRequest(identifier: id, content: extraContent, trigger: extraTrigger))

                alreadySent += 1
                UserDefaults.standard.set(alreadySent, forKey: "totalExtraRemindersSentToday")
            }
        }
    }
}


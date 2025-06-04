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
    @Published var showingDailySummary = false

    func scheduleDailyReminders(
        morningHour: Int,
        morningMinute: Int,
        nightHour: Int,
        nightMinute: Int,
        extraReminders: Int
    ) {
        let center = UNUserNotificationCenter.current()

        let idsToRemove = ["morningReminder", "nightReminder"] + (1...10).map { "extraReminder\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: idsToRemove)

        // Random Morning Reminder
        let morningTitles = [
            "Still in bed?",
            "Time waits for no one!",
            "Your tasks are collecting dust already.",
            "The world’s moving. Are you?",
            "Every day you delay is a day you regret."
        ]
        let morningBodies = [
            "You said today would be different. Prove it.",
            "Start your day by creating your to-do list!",
            "Even the sun showed up. Where are you?",
            "This to-do list won’t write itself, you know.",
            "Let’s aim for progress today, not excuses."
        ]
        let morningContent = UNMutableNotificationContent()
        morningContent.title = morningTitles.randomElement() ?? "Plan Your Day"
        morningContent.body = morningBodies.randomElement() ?? "Start your day by creating your to-do list!"
        morningContent.sound = .default

        let morningTrigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: morningHour, minute: morningMinute),
            repeats: true
        )
        center.add(UNNotificationRequest(identifier: "morningReminder", content: morningContent, trigger: morningTrigger))

        // Random Night Reminder
        let nightTitles = [
            "Time to face the truth…",
            "Another day gone. Did you do anything?",
            "Let’s pretend we accomplished things today.",
            "Before you sleep, confront the to-do monster."
        ]
        let nightBodies = [
            "Check off what you did. Or don’t. It’s your conscience.",
            "Hope you weren’t just rearranging icons all day.",
            "Reflection time: honest or delusional?",
            "How many ‘start tomorrow’ promises are you up to now?"
        ]
        let nightContent = UNMutableNotificationContent()
        nightContent.title = nightTitles.randomElement() ?? "Review Your Day"
        nightContent.body = nightBodies.randomElement() ?? "Don’t forget to check off completed tasks!"
        nightContent.sound = .default

        let nightTrigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: nightHour, minute: nightMinute),
            repeats: true
        )
        center.add(UNNotificationRequest(identifier: "nightReminder", content: nightContent, trigger: nightTrigger))

        // Extra Reminders
        if extraReminders > 0 {
            let startMinutes = morningHour * 60 + morningMinute
            let endMinutes = nightHour * 60 + nightMinute
            guard endMinutes > startMinutes else {
                print("Invalid time range for extra reminders.")
                return
            }

            let interval = (endMinutes - startMinutes) / (extraReminders + 1)

            let extraBodies = [
                "You swore this app would help. Help yourself first.",
                "Doing nothing is also a choice. A bad one.",
                "Don’t make me send another reminder.",
                "You’re doing great… at dodging your goals.",
                "This is your sign to do *something* productive.",
                "Your to-dos are aging like fine milk.",
                "Still waiting for you to act…",
                "Another hour, another broken promise?"
            ]

            for i in 1...extraReminders {
                let scheduledMinutes = startMinutes + i * interval
                let hour = scheduledMinutes / 60
                let minute = scheduledMinutes % 60

                let extraContent = UNMutableNotificationContent()
                extraContent.title = "Task Check-In"
                extraContent.body = extraBodies.randomElement() ?? "Take a moment to update your to-dos."
                extraContent.sound = .default

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

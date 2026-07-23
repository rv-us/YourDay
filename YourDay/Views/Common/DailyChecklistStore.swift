//
//  DailyChecklistStore.swift
//  YourDay
//
//  Shared persistence for the daily "Start your day" checklist (Migrate / Schedule /
//  New tasks / Recap). Both ContentView (reappear gating) and DailyDashboardView
//  (tile display) read/write the same UserDefaults keys, so completing a step in one
//  place is immediately reflected in the other. Each step stores the yyyy-MM-dd it was
//  completed on; a step counts as "done today" only when its stored date == today's.
//

import Foundation

enum DailyChecklistStore {
    // Keys are shared with @AppStorage in DailyDashboardView (same UserDefaults store).
    static let migrateDoneKey = "checklistMigrateDoneDate"
    static let scheduleDoneKey = "checklistScheduleDoneDate"
    static let newTasksDoneKey = "checklistNewTasksDoneDate"
    static let recapViewedKey = "checklistRecapViewedDate"   // cosmetic, non-gating
    static let skippedKey = "dailyChecklistSkippedDate"

    /// Same yyyy-MM-dd format used across ContentView's new-day logic.
    static func todayString(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Calendar.current.startOfDay(for: date))
    }

    private static func isMarkedToday(_ key: String, today: String) -> Bool {
        UserDefaults.standard.string(forKey: key) == today
    }

    private static func mark(_ key: String, today: String) {
        UserDefaults.standard.set(today, forKey: key)
    }

    // MARK: - Per-step completion

    static func isMigrateDone(today: String) -> Bool { isMarkedToday(migrateDoneKey, today: today) }
    static func isScheduleDone(today: String) -> Bool { isMarkedToday(scheduleDoneKey, today: today) }
    static func isNewTasksDone(today: String) -> Bool { isMarkedToday(newTasksDoneKey, today: today) }
    static func isRecapViewed(today: String) -> Bool { isMarkedToday(recapViewedKey, today: today) }

    static func markMigrateDone(today: String) { mark(migrateDoneKey, today: today) }
    static func markScheduleDone(today: String) { mark(scheduleDoneKey, today: today) }
    static func markNewTasksDone(today: String) { mark(newTasksDoneKey, today: today) }
    static func markRecapViewed(today: String) { mark(recapViewedKey, today: today) }

    // MARK: - Skip

    static func isSkipped(today: String) -> Bool { isMarkedToday(skippedKey, today: today) }
    static func markSkipped(today: String) { mark(skippedKey, today: today) }

    // MARK: - Gate

    /// The popup stops reappearing once the three action steps are done (Recap is a
    /// shortcut and does not gate). Skip is handled separately by the caller.
    static func isGateComplete(today: String) -> Bool {
        isMigrateDone(today: today) && isScheduleDone(today: today) && isNewTasksDone(today: today)
    }
}

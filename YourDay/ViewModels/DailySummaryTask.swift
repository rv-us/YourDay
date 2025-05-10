//
//  DailySummaryTask.swift
//  YourDay
//
//  Created by Rachit Verma on 5/7/25.
//
import Foundation
import SwiftData

@Model
class DailySummaryTask {
    var id: UUID
    var taskTitle: String
    var date: Date
    var totalPoints: Double
    var subtaskTitles: [String]
    var subtaskPoints: [Double]
    var mainTaskCompleted: Bool
    var taskMaxPossiblePoints: Double

    // Daily completion snapshot
    var dayCompletionSnapshot_CompletedCount: Int
    var dayCompletionSnapshot_TotalTasksCount: Int

    // XP and Leveling snapshot for this day's summary
    var levelBeforeXP: Int
    var xpBeforeXP: Double // XP towards next level, before today's gain
    var levelAfterXP: Int
    var xpAfterXP: Double  // XP towards next level, after today's gain
    var xpEarnedOnDate: Double // Actual XP points gained on this date
    var xpToNextLevelAfterXP: Double // Total XP needed for the level player is at *after* this day's XP gain

    init(
        taskTitle: String,
        date: Date,
        totalPoints: Double,
        subtaskTitles: [String],
        subtaskPoints: [Double],
        mainTaskCompleted: Bool,
        taskMaxPossiblePoints: Double,
        dayCompletionSnapshot_CompletedCount: Int,
        dayCompletionSnapshot_TotalTasksCount: Int,
        // New parameters for XP/Level
        levelBeforeXP: Int,
        xpBeforeXP: Double,
        levelAfterXP: Int,
        xpAfterXP: Double,
        xpEarnedOnDate: Double,
        xpToNextLevelAfterXP: Double
    ) {
        self.id = UUID()
        self.taskTitle = taskTitle
        self.date = date
        self.totalPoints = totalPoints
        self.subtaskTitles = subtaskTitles
        self.subtaskPoints = subtaskPoints
        self.mainTaskCompleted = mainTaskCompleted
        self.taskMaxPossiblePoints = taskMaxPossiblePoints
        self.dayCompletionSnapshot_CompletedCount = dayCompletionSnapshot_CompletedCount
        self.dayCompletionSnapshot_TotalTasksCount = dayCompletionSnapshot_TotalTasksCount
        self.levelBeforeXP = levelBeforeXP
        self.xpBeforeXP = xpBeforeXP
        self.levelAfterXP = levelAfterXP
        self.xpAfterXP = xpAfterXP
        self.xpEarnedOnDate = xpEarnedOnDate
        self.xpToNextLevelAfterXP = xpToNextLevelAfterXP
    }
}

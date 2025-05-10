//
//  PointManager.swift
//  YourDay
//
//  Created by Rachit Verma on 5/4/25.
//

import Foundation
import SwiftData

struct TaskPointResult: Identifiable {
    let id = UUID()
    let title: String
    let date: Date
    let basePoints: Double
    let subtaskPoints: [(title: String, earned: Double)]
    let totalPoints: Double
    let mainTaskCompletedOnTargetDay: Bool
}

class PointManager {
    static let maxPerTaskPercentage: Double = 0.20

    static func evaluateDailyPoints(context: ModelContext, tasks: [TodoItem], on date: Date = Date()) -> (total: Double, breakdown: [TaskPointResult]) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let descriptor = FetchDescriptor<PlayerStats>()
        // Ensure PlayerStats exists, or create a new one.
        let stats = (try? context.fetch(descriptor).first) ?? PlayerStats()
        // If stats was just created, insert it so it's managed.
        if stats.modelContext == nil {
            context.insert(stats)
        }


        if let lastEval = stats.lastEvaluated,
           calendar.isDate(lastEval, inSameDayAs: yesterday) {
            print("Points for \(calendar.startOfDay(for: yesterday)) already evaluated.")
            return (0.0, [])
        }

        let (earnedPoints, breakdown) = calculatePointsEarned(
            for: tasks,
            on: today,
            playerGardenValue: stats.gardenValue
        )

        let completedMainTasksForYesterday = breakdown.filter { $0.mainTaskCompletedOnTargetDay }.count
        let totalTasksWhenEvaluated = tasks.count

        // Store player's state *before* adding today's XP
        let levelBeforeXP = stats.playerLevel
        let xpBeforeXP = stats.currentXP
        let xpEarnedToday = earnedPoints // Points earned today are XP

        if earnedPoints > 0 {
            stats.totalPoints += earnedPoints // Add to currency
            stats.addXP(earnedPoints)        // Add to experience and handle level ups
        }
        
        // Player's state *after* adding today's XP
        let levelAfterXP = stats.playerLevel
        let xpAfterXP = stats.currentXP
        let xpToNextLevelAfterXP = PlayerStats.xpRequiredForNextLevel(currentLevel: stats.playerLevel)


        for result in breakdown where result.totalPoints > 0 {
            let subtaskTitles = result.subtaskPoints.map { $0.title }
            let subtaskPointsValues = result.subtaskPoints.map { $0.earned }

            let summary = DailySummaryTask(
                taskTitle: result.title,
                date: result.date,
                totalPoints: result.totalPoints,
                subtaskTitles: subtaskTitles,
                subtaskPoints: subtaskPointsValues,
                mainTaskCompleted: result.mainTaskCompletedOnTargetDay,
                taskMaxPossiblePoints: result.basePoints,
                dayCompletionSnapshot_CompletedCount: completedMainTasksForYesterday,
                dayCompletionSnapshot_TotalTasksCount: totalTasksWhenEvaluated,
                // Add new XP and level info
                levelBeforeXP: levelBeforeXP,
                xpBeforeXP: xpBeforeXP,
                levelAfterXP: levelAfterXP,
                xpAfterXP: xpAfterXP,
                xpEarnedOnDate: xpEarnedToday,
                xpToNextLevelAfterXP: xpToNextLevelAfterXP
            )
            context.insert(summary)
        }
        
        stats.lastEvaluated = yesterday
        // No need to call context.insert(stats) again if it was already inserted or fetched.
        // SwiftData tracks changes to managed objects.

        return (earnedPoints, breakdown)
    }

    static func calculatePointsEarned(
        for tasks: [TodoItem],
        on evaluationDate: Date = Date(),
        playerGardenValue: Double
    ) -> (total: Double, breakdown: [TaskPointResult]) {
        let calendar = Calendar.current
        let targetCompletionDay = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: evaluationDate))!

        var totalEarnedOverall = 0.0
        var results: [TaskPointResult] = []

        let effectiveGardenValue = max(playerGardenValue, 1.0)
        let maxPointsPerSingleTask = effectiveGardenValue * maxPerTaskPercentage

        for task in tasks {
            var subtaskBreakdown: [(title: String, earned: Double)] = []
            var earnedForTask: Double = 0.0
            
            let isMainTaskCompletedOnTargetDay = task.completedAt.map { calendar.isDate($0, inSameDayAs: targetCompletionDay) } ?? false

            if task.subtasks.isEmpty {
                if isMainTaskCompletedOnTargetDay {
                    earnedForTask = maxPointsPerSingleTask
                }
            } else {
                let perSubtaskPoints = task.subtasks.isEmpty ? 0 : maxPointsPerSingleTask / Double(task.subtasks.count)
                for sub in task.subtasks {
                    if let subCompletedAt = sub.completedAt,
                       calendar.isDate(subCompletedAt, inSameDayAs: targetCompletionDay) {
                        subtaskBreakdown.append((sub.title, perSubtaskPoints))
                        earnedForTask += perSubtaskPoints
                    } else {
                        subtaskBreakdown.append((sub.title, 0))
                    }
                }
            }

            if earnedForTask > 0 || isMainTaskCompletedOnTargetDay {
                totalEarnedOverall += earnedForTask
                results.append(TaskPointResult(
                    title: task.title,
                    date: targetCompletionDay,
                    basePoints: maxPointsPerSingleTask,
                    subtaskPoints: subtaskBreakdown,
                    totalPoints: earnedForTask,
                    mainTaskCompletedOnTargetDay: isMainTaskCompletedOnTargetDay
                ))
            }
        }
        return (total: round(totalEarnedOverall), breakdown: results)
    }
}

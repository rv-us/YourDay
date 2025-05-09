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
    let date: Date // Represents the day for which points were awarded (i.e., "yesterday")
    let basePoints: Double // Max potential points for this task (now based on gardenValue)
    let subtaskPoints: [(title: String, earned: Double)]
    let totalPoints: Double // Total points earned for this task on the evaluation day
    let mainTaskCompletedOnTargetDay: Bool // Was the main task itself completed on the target day?
}

class PointManager {
    // This still defines the *proportion* a task can be of the daily potential,
    // but the daily potential is now tied to gardenValue.
    static let maxPerTaskPercentage: Double = 0.20 // Max 5 tasks contribute to the dynamic daily max

    static func evaluateDailyPoints(context: ModelContext, tasks: [TodoItem], on date: Date = Date()) -> (total: Double, breakdown: [TaskPointResult]) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let descriptor = FetchDescriptor<PlayerStats>()
        let stats = (try? context.fetch(descriptor).first) ?? PlayerStats()

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
                taskMaxPossiblePoints: result.basePoints // Save the calculated basePoints
            )
            context.insert(summary)
        }

        if earnedPoints > 0 {
            stats.totalPoints += earnedPoints
        }
        stats.lastEvaluated = yesterday
        
        context.insert(stats)

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
            // var hasAnyActivityOnTargetDay = false // This variable is not used, can be removed if not needed for other logic

            let isMainTaskCompletedOnTargetDay = task.completedAt.map { calendar.isDate($0, inSameDayAs: targetCompletionDay) } ?? false

            if task.subtasks.isEmpty {
                if isMainTaskCompletedOnTargetDay {
                    earnedForTask = maxPointsPerSingleTask
                    // hasAnyActivityOnTargetDay = true
                }
            } else {
                let perSubtaskPoints = task.subtasks.isEmpty ? 0 : maxPointsPerSingleTask / Double(task.subtasks.count)
                var anySubtaskCompletedOnTargetDay = false

                for sub in task.subtasks {
                    if let subCompletedAt = sub.completedAt,
                       calendar.isDate(subCompletedAt, inSameDayAs: targetCompletionDay) {
                        subtaskBreakdown.append((sub.title, perSubtaskPoints))
                        earnedForTask += perSubtaskPoints
                        anySubtaskCompletedOnTargetDay = true
                    } else {
                        subtaskBreakdown.append((sub.title, 0))
                    }
                }
                // if anySubtaskCompletedOnTargetDay {
                //    hasAnyActivityOnTargetDay = true
                // }
            }

            if earnedForTask > 0 {
                totalEarnedOverall += earnedForTask
                results.append(TaskPointResult(
                    title: task.title,
                    date: targetCompletionDay,
                    basePoints: maxPointsPerSingleTask, // This is the value we want to persist
                    subtaskPoints: subtaskBreakdown,
                    totalPoints: earnedForTask,
                    mainTaskCompletedOnTargetDay: isMainTaskCompletedOnTargetDay
                ))
            } else if isMainTaskCompletedOnTargetDay {
                // Logic for 0-point completed tasks (currently not added to results)
            }
        }
        return (total: round(totalEarnedOverall), breakdown: results)
    }
}

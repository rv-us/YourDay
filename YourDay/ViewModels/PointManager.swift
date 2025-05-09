//
//  PointManager.swift
//  YourDay
//
//  Created by Rachit Verma on 5/4/25.
//

// PointManager.swift

import Foundation
import SwiftData

struct TaskPointResult: Identifiable {
    let id = UUID()
    let title: String
    let date: Date // Represents the day for which points were awarded (i.e., "yesterday")
    let basePoints: Double // Max potential points for this task
    let subtaskPoints: [(title: String, earned: Double)]
    let totalPoints: Double // Total points earned for this task on the evaluation day
    let mainTaskCompletedOnTargetDay: Bool // Was the main task itself completed on the target day?
}

class PointManager {
    static var maxPointsPerDay: Double = 100.0
    static let maxPerTaskPercentage: Double = 0.20 // Max 5 tasks contribute to daily 100 points

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

        let (earnedPoints, breakdown) = calculatePointsEarned(for: tasks, on: today) // 'today' is the evaluation execution day

        for result in breakdown where result.totalPoints > 0 { // Only save if points were actually earned
            let subtaskTitles = result.subtaskPoints.map { $0.title }
            let subtaskPointsValues = result.subtaskPoints.map { $0.earned }

            let summary = DailySummaryTask(
                taskTitle: result.title,
                date: result.date, // This will be 'yesterday'
                totalPoints: result.totalPoints,
                subtaskTitles: subtaskTitles,
                subtaskPoints: subtaskPointsValues,
                mainTaskCompleted: result.mainTaskCompletedOnTargetDay // New field
            )
            context.insert(summary)
        }

        if earnedPoints > 0 {
            stats.totalPoints += earnedPoints
        }
        stats.lastEvaluated = yesterday // Mark 'yesterday' as evaluated
        
        // SwiftData handles insert vs update automatically if 'stats' was fetched
        // If it's a new PlayerStats object, it will be inserted.
        // No need to check if context already contains it before inserting.
        context.insert(stats)


        return (earnedPoints, breakdown)
    }

    static func calculatePointsEarned(for tasks: [TodoItem], on evaluationDate: Date = Date()) -> (total: Double, breakdown: [TaskPointResult]) {
        let calendar = Calendar.current
        // Points are awarded for completions on the day *before* the evaluationDate.
        let targetCompletionDay = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: evaluationDate))!

        var totalEarnedOverall = 0.0
        var results: [TaskPointResult] = []

        for task in tasks {
            let maxTaskPoints = maxPointsPerDay * maxPerTaskPercentage
            var subtaskBreakdown: [(title: String, earned: Double)] = []
            var earnedForTask: Double = 0.0
            var hasAnyActivityOnTargetDay = false

            let isMainTaskCompletedOnTargetDay = task.completedAt.map { calendar.isDate($0, inSameDayAs: targetCompletionDay) } ?? false

            if task.subtasks.isEmpty {
                if isMainTaskCompletedOnTargetDay {
                    earnedForTask = maxTaskPoints
                    hasAnyActivityOnTargetDay = true
                }
            } else {
                // If task has subtasks, points are derived from subtasks.
                // The main task completion status (isMainTaskCompletedOnTargetDay) is noted but doesn't add separate points
                // if subtasks exist, as points are distributed among them.
                let perSubtaskPoints = task.subtasks.isEmpty ? 0 : maxTaskPoints / Double(task.subtasks.count)
                var anySubtaskCompletedOnTargetDay = false

                for sub in task.subtasks {
                    if let subCompletedAt = sub.completedAt,
                       calendar.isDate(subCompletedAt, inSameDayAs: targetCompletionDay) {
                        subtaskBreakdown.append((sub.title, perSubtaskPoints))
                        earnedForTask += perSubtaskPoints
                        anySubtaskCompletedOnTargetDay = true
                    } else {
                        subtaskBreakdown.append((sub.title, 0)) // Still include for full breakdown, but 0 points
                    }
                }
                if anySubtaskCompletedOnTargetDay {
                    hasAnyActivityOnTargetDay = true
                }
            }

            // Add to results if points were earned OR if the main task was specifically completed on the target day
            // (even if it had subtasks and none were completed, resulting in 0 points for that day but still marking its completion).
            // OR if any subtask activity occurred.
            if earnedForTask > 0 || isMainTaskCompletedOnTargetDay || hasAnyActivityOnTargetDay {
                 // We only care about results if points were earned.
                 // If a main task was completed but yielded 0 points (e.g. has subtasks but none done yesterday)
                 // it won't contribute to totalEarnedOverall unless earnedForTask > 0.
                 // The DailySummaryTask will only be created if totalPoints > 0 anyway.
                if earnedForTask > 0 {
                    totalEarnedOverall += earnedForTask
                    results.append(TaskPointResult(
                        title: task.title,
                        date: targetCompletionDay, // Date for which points are recorded
                        basePoints: maxTaskPoints,
                        subtaskPoints: subtaskBreakdown,
                        totalPoints: earnedForTask,
                        mainTaskCompletedOnTargetDay: isMainTaskCompletedOnTargetDay
                    ))
                } else if isMainTaskCompletedOnTargetDay {
                    // If main task was completed but no points (e.g. task with subtasks, none completed yesterday)
                    // We still want to record it in the breakdown if desired for UI, but with 0 points.
                    // For this iteration, we'll only add to results if points were earned.
                    // This can be revisited if LastDayView needs to show 0-point completed tasks.
                    // The current DailySummaryTask creation logic (where totalPoints > 0) would filter this out anyway.
                }
            }
        }
        return (total: round(totalEarnedOverall), breakdown: results)
    }
}

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
}

class PointManager {
    static var maxPointsPerDay: Double = 100.0
    static let maxPerTaskPercentage: Double = 0.20 // 20%

    static func evaluateDailyPoints(context: ModelContext, tasks: [TodoItem], on date: Date = Date()) -> (total: Double, breakdown: [TaskPointResult]) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        // Fetch or create PlayerStats
        let descriptor = FetchDescriptor<PlayerStats>()
        let stats = (try? context.fetch(descriptor).first) ?? PlayerStats()

        // Prevent double evaluation
        if let lastEval = stats.lastEvaluated,
           calendar.isDate(lastEval, inSameDayAs: yesterday) {
            return (0.0, []) // Already calculated
        }

        let (earnedPoints, breakdown) = calculatePointsEarned(for: tasks, on: today)

        stats.totalPoints += earnedPoints
        stats.lastEvaluated = yesterday
        context.insert(stats)

        return (earnedPoints, breakdown)
    }

    static func calculatePointsEarned(for tasks: [TodoItem], on date: Date = Date()) -> (total: Double, breakdown: [TaskPointResult]) {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date))!

        var totalEarned = 0.0
        var results: [TaskPointResult] = []

        for task in tasks {
            guard let completed = task.completedAt,
                  calendar.isDate(completed, inSameDayAs: yesterday) else {
                continue
            }

            let maxTaskPoints = maxPointsPerDay * maxPerTaskPercentage
            var subtaskBreakdown: [(String, Double)] = []
            var earnedForTask: Double = 0.0

            if task.subtasks.isEmpty {
                earnedForTask = maxTaskPoints
            } else {
                let perSubtask = maxTaskPoints / Double(task.subtasks.count)
                for sub in task.subtasks {
                    if let completedAt = sub.completedAt,
                       calendar.isDate(completedAt, inSameDayAs: yesterday) {
                        subtaskBreakdown.append((sub.title, perSubtask))
                        earnedForTask += perSubtask
                    } else {
                        subtaskBreakdown.append((sub.title, 0))
                    }
                }
            }

            totalEarned += earnedForTask

            results.append(TaskPointResult(
                title: task.title,
                date: completed,
                basePoints: maxTaskPoints,
                subtaskPoints: subtaskBreakdown,
                totalPoints: earnedForTask
            ))
        }

        return (total: round(totalEarned), breakdown: results)
    }
}

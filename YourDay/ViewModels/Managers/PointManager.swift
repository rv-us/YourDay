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
    let origin: TaskOrigin
    /// Matches `TodoItem.localTaskId` / `sharedTaskId` for proof bonus; empty when reconstructed from summary-only UI.
    let localTaskId: String
    let sharedTaskId: String?
}

class PointManager {
    static let maxPerTaskPercentage: Double = 0.20
    
    static func calculateTaskCompletionStreak(
        completedMainTasksForYesterday: Int,
        previousLastEvaluated: Date?,
        yesterday: Date,
        previousCompletedTasks: Int,
        previousStreak: Int,
        calendar: Calendar = .current
    ) -> Int {
        guard completedMainTasksForYesterday > 0 else { return 0 }
        guard let previousLastEvaluated else { return 1 }
        
        guard let dayBeforeYesterday = calendar.date(byAdding: .day, value: -1, to: yesterday) else {
            return 1
        }
        
        let wasPreviousDayEvaluated = calendar.isDate(previousLastEvaluated, inSameDayAs: dayBeforeYesterday)
        if wasPreviousDayEvaluated && previousCompletedTasks > 0 {
            return max(previousStreak, 0) + 1
        }
        return 1
    }

    private static func proofBonusMultiplier(
        for result: TaskPointResult,
        eligibleLocalTaskIds: Set<String>,
        eligibleSharedTaskIds: Set<String>
    ) -> Double {
        if eligibleLocalTaskIds.contains(result.localTaskId) { return 1.5 }
        if let sid = result.sharedTaskId, eligibleSharedTaskIds.contains(sid) { return 1.5 }
        return 1.0
    }

    private static func proofVoteRollup(
        for result: TaskPointResult,
        proofVoteRollupsByLocalTaskId: [String: ProofFeedVoteRollup],
        proofVoteRollupsBySharedTaskId: [String: ProofFeedVoteRollup]
    ) -> ProofFeedVoteRollup? {
        if let r = proofVoteRollupsByLocalTaskId[result.localTaskId] { return r }
        if let sid = result.sharedTaskId, let r = proofVoteRollupsBySharedTaskId[sid] { return r }
        return nil
    }

    static func evaluateDailyPoints(
        context: ModelContext,
        tasks: [TodoItem],
        on date: Date = Date(),
        proofBonusEligibleLocalTaskIds: Set<String> = [],
        proofBonusEligibleSharedTaskIds: Set<String> = [],
        proofVoteRollupsByLocalTaskId: [String: ProofFeedVoteRollup] = [:],
        proofVoteRollupsBySharedTaskId: [String: ProofFeedVoteRollup] = [:]
    ) -> (total: Double, breakdown: [TaskPointResult]) {
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

        let adjustedTotal = breakdown.reduce(0.0) { partial, result in
            partial + result.totalPoints * proofBonusMultiplier(
                for: result,
                eligibleLocalTaskIds: proofBonusEligibleLocalTaskIds,
                eligibleSharedTaskIds: proofBonusEligibleSharedTaskIds
            )
        }
        print("[DailyEval] evaluateDailyPoints: baseEarned=\(earnedPoints) adjustedTotal=\(adjustedTotal) tasks=\(tasks.count) proofBonusLocals=\(proofBonusEligibleLocalTaskIds.count) proofBonusShared=\(proofBonusEligibleSharedTaskIds.count)")

        let previousLastEvaluated = stats.lastEvaluated
        let previousCompletedTasks = stats.lastDailyCompletedTasks
        let previousStreak = stats.taskCompletionStreak

        let completedMainTasksForYesterday = breakdown.filter { $0.mainTaskCompletedOnTargetDay }.count
        let totalTasksWhenEvaluated = tasks.count
        let updatedStreak = calculateTaskCompletionStreak(
            completedMainTasksForYesterday: completedMainTasksForYesterday,
            previousLastEvaluated: previousLastEvaluated,
            yesterday: yesterday,
            previousCompletedTasks: previousCompletedTasks,
            previousStreak: previousStreak,
            calendar: calendar
        )

        // Store player's state *before* adding today's XP
        let levelBeforeXP = stats.playerLevel
        let xpBeforeXP = stats.currentXP
        let xpEarnedToday = adjustedTotal

        if adjustedTotal > 0 {
            stats.totalPoints += adjustedTotal
            stats.addXP(adjustedTotal)
        }
        
        // Player's state *after* adding today's XP
        let levelAfterXP = stats.playerLevel
        let xpAfterXP = stats.currentXP
        let xpToNextLevelAfterXP = PlayerStats.xpRequiredForNextLevel(currentLevel: stats.playerLevel)


        for result in breakdown where result.totalPoints > 0 {
            let m = proofBonusMultiplier(
                for: result,
                eligibleLocalTaskIds: proofBonusEligibleLocalTaskIds,
                eligibleSharedTaskIds: proofBonusEligibleSharedTaskIds
            )
            let rollup = proofVoteRollup(
                for: result,
                proofVoteRollupsByLocalTaskId: proofVoteRollupsByLocalTaskId,
                proofVoteRollupsBySharedTaskId: proofVoteRollupsBySharedTaskId
            )
            let hasProof = rollup != nil
            let baseTaskPoints = result.totalPoints
            let bonusExtra = m > 1 ? baseTaskPoints * (m - 1.0) : 0

            let subtaskTitles = result.subtaskPoints.map { $0.title }
            let subtaskPointsValues = result.subtaskPoints.map { $0.earned * m }

            let summary = DailySummaryTask(
                taskTitle: result.title,
                date: result.date,
                totalPoints: result.totalPoints * m,
                subtaskTitles: subtaskTitles,
                subtaskPoints: subtaskPointsValues,
                mainTaskCompleted: result.mainTaskCompletedOnTargetDay,
                taskMaxPossiblePoints: result.basePoints * m,
                origin: result.origin,
                dayCompletionSnapshot_CompletedCount: completedMainTasksForYesterday,
                dayCompletionSnapshot_TotalTasksCount: totalTasksWhenEvaluated,
                // Add new XP and level info
                levelBeforeXP: levelBeforeXP,
                xpBeforeXP: xpBeforeXP,
                levelAfterXP: levelAfterXP,
                xpAfterXP: xpAfterXP,
                xpEarnedOnDate: xpEarnedToday,
                xpToNextLevelAfterXP: xpToNextLevelAfterXP,
                hasProofFeedBreakdown: hasProof,
                proofFeedCheckVotes: rollup?.allCheckVotes ?? 0,
                proofFeedXVotes: rollup?.allXVotes ?? 0,
                proofFeedPointsMultiplierApplied: m,
                proofFeedBonusExtraPoints: bonusExtra
            )
            context.insert(summary)
        }
        
        stats.lastDailyPointsEarned = adjustedTotal
        stats.lastDailyCompletedTasks = completedMainTasksForYesterday
        stats.lastDailyTotalTasks = totalTasksWhenEvaluated
        stats.taskCompletionStreak = updatedStreak
        stats.lastEvaluated = yesterday
        // No need to call context.insert(stats) again if it was already inserted or fetched.
        // SwiftData tracks changes to managed objects.

        let scaledBreakdown: [TaskPointResult] = breakdown.map { result in
            let m = proofBonusMultiplier(
                for: result,
                eligibleLocalTaskIds: proofBonusEligibleLocalTaskIds,
                eligibleSharedTaskIds: proofBonusEligibleSharedTaskIds
            )
            return TaskPointResult(
                title: result.title,
                date: result.date,
                basePoints: result.basePoints * m,
                subtaskPoints: result.subtaskPoints.map { ($0.title, $0.earned * m) },
                totalPoints: result.totalPoints * m,
                mainTaskCompletedOnTargetDay: result.mainTaskCompletedOnTargetDay,
                origin: result.origin,
                localTaskId: result.localTaskId,
                sharedTaskId: result.sharedTaskId
            )
        }

        return (adjustedTotal, scaledBreakdown)
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
                    mainTaskCompletedOnTargetDay: isMainTaskCompletedOnTargetDay,
                    origin: task.origin,
                    localTaskId: task.localTaskId,
                    sharedTaskId: task.sharedTaskId
                ))
            }
        }
        return (total: round(totalEarnedOverall), breakdown: results)
    }
}

import Foundation
import Testing
@testable import YourDay

struct DashboardFriendStatsTests {
    @Test func taskStreakIncrementsOnConsecutiveActiveDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let yesterday = date("2026-02-10")
        let previousLastEvaluated = date("2026-02-09")

        let streak = PointManager.calculateTaskCompletionStreak(
            completedMainTasksForYesterday: 3,
            previousLastEvaluated: previousLastEvaluated,
            yesterday: yesterday,
            previousCompletedTasks: 2,
            previousStreak: 4,
            calendar: calendar
        )

        #expect(streak == 5)
    }

    @Test func taskStreakResetsToZeroWhenNoCompletedTasksYesterday() {
        let streak = PointManager.calculateTaskCompletionStreak(
            completedMainTasksForYesterday: 0,
            previousLastEvaluated: date("2026-02-09"),
            yesterday: date("2026-02-10"),
            previousCompletedTasks: 5,
            previousStreak: 7
        )

        #expect(streak == 0)
    }

    @Test func taskStreakRestartsAfterGapEvenWithPreviousStreak() {
        let streak = PointManager.calculateTaskCompletionStreak(
            completedMainTasksForYesterday: 1,
            previousLastEvaluated: date("2026-02-07"),
            yesterday: date("2026-02-10"),
            previousCompletedTasks: 1,
            previousStreak: 4
        )

        #expect(streak == 1)
    }

    @Test func staleAndNoActivityMappingMatchesRules() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let referenceDate = date("2026-02-11")
        let yesterday = date("2026-02-10")

        let staleCard = FriendDashboardStats(
            userId: "u1",
            displayName: "Stale",
            yesterdayPoints: 20,
            completedTasksYesterday: 2,
            totalTasksYesterday: 3,
            taskStreak: 2,
            lastEvaluated: date("2026-02-08")
        )
        #expect(staleCard.isStale(referenceDate: referenceDate, calendar: calendar))
        #expect(staleCard.isNoActivityYesterday(referenceDate: referenceDate, calendar: calendar))

        let zeroCompletionCard = FriendDashboardStats(
            userId: "u2",
            displayName: "Zero",
            yesterdayPoints: 0,
            completedTasksYesterday: 0,
            totalTasksYesterday: 4,
            taskStreak: 0,
            lastEvaluated: yesterday
        )
        #expect(!zeroCompletionCard.isStale(referenceDate: referenceDate, calendar: calendar))
        #expect(zeroCompletionCard.isNoActivityYesterday(referenceDate: referenceDate, calendar: calendar))

        let activeCard = FriendDashboardStats(
            userId: "u3",
            displayName: "Active",
            yesterdayPoints: 10,
            completedTasksYesterday: 2,
            totalTasksYesterday: 4,
            taskStreak: 1,
            lastEvaluated: yesterday
        )
        #expect(!activeCard.isStale(referenceDate: referenceDate, calendar: calendar))
        #expect(!activeCard.isNoActivityYesterday(referenceDate: referenceDate, calendar: calendar))
    }

    @Test func cardsSortByPointsThenStreakThenName() {
        let cards = [
            FriendDashboardStats(
                userId: "u1",
                displayName: "Zara",
                yesterdayPoints: 10,
                completedTasksYesterday: 2,
                totalTasksYesterday: 3,
                taskStreak: 5,
                lastEvaluated: date("2026-02-10")
            ),
            FriendDashboardStats(
                userId: "u2",
                displayName: "Alex",
                yesterdayPoints: 30,
                completedTasksYesterday: 1,
                totalTasksYesterday: 3,
                taskStreak: 1,
                lastEvaluated: date("2026-02-10")
            ),
            FriendDashboardStats(
                userId: "u3",
                displayName: "Ben",
                yesterdayPoints: 10,
                completedTasksYesterday: 2,
                totalTasksYesterday: 3,
                taskStreak: 6,
                lastEvaluated: date("2026-02-10")
            ),
            FriendDashboardStats(
                userId: "u4",
                displayName: "Amy",
                yesterdayPoints: 10,
                completedTasksYesterday: 2,
                totalTasksYesterday: 3,
                taskStreak: 6,
                lastEvaluated: date("2026-02-10")
            )
        ]

        let sorted = DashboardFriendStatsViewModel.sortCards(cards)
        #expect(sorted.map(\.displayName) == ["Alex", "Amy", "Ben", "Zara"])
    }
}

private func date(_ string: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.date(from: string) ?? Date(timeIntervalSince1970: 0)
}

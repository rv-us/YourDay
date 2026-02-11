import Foundation

struct FriendDashboardStats: Identifiable {
    let userId: String
    let displayName: String
    let yesterdayPoints: Double
    let completedTasksYesterday: Int
    let totalTasksYesterday: Int
    let taskStreak: Int
    let lastEvaluated: Date?

    var id: String { userId }

    static func isLastEvaluatedStale(
        _ lastEvaluated: Date?,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let lastEvaluated else { return true }
        let today = calendar.startOfDay(for: referenceDate)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
            return true
        }
        return !calendar.isDate(lastEvaluated, inSameDayAs: yesterday)
    }

    func isStale(referenceDate: Date = Date(), calendar: Calendar = .current) -> Bool {
        Self.isLastEvaluatedStale(lastEvaluated, referenceDate: referenceDate, calendar: calendar)
    }

    func isNoActivityYesterday(referenceDate: Date = Date(), calendar: Calendar = .current) -> Bool {
        isStale(referenceDate: referenceDate, calendar: calendar) || completedTasksYesterday == 0
    }

    var isStale: Bool { isStale() }
    var isNoActivityYesterday: Bool { isNoActivityYesterday() }
}

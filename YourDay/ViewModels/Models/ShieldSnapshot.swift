import Foundation

struct ScheduledTaskBrief: Codable, Hashable {
    var title: String
    var startTime: Date?
    var endTime: Date?
    var isDone: Bool
}

struct ShieldSnapshot: Codable {
    var dayKey: String
    var hasPlannedDay: Bool
    var scheduledTasks: [ScheduledTaskBrief]
    var completedCount: Int
    var totalScheduledCount: Int
    var penaltyAmount: Int
    var updatedAt: Date

    static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func dayKey(for date: Date = Date()) -> String {
        dayKeyFormatter.string(from: date)
    }

    var openTaskTitles: [String] {
        scheduledTasks.filter { !$0.isDone }.map(\.title)
    }

    func activeTask(at date: Date = Date()) -> ScheduledTaskBrief? {
        activeTasks(at: date).first
    }

    func activeTasks(at date: Date = Date()) -> [ScheduledTaskBrief] {
        scheduledTasks.filter { task in
            guard !task.isDone,
                  let start = task.startTime,
                  let end = task.endTime else { return false }
            return start <= date && date < end
        }
    }

    func isInTaskSlot(at date: Date = Date()) -> Bool {
        !activeTasks(at: date).isEmpty
    }
}

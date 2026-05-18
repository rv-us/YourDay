import Foundation

struct ScheduledTaskBrief: Codable, Hashable {
    var title: String
    var startTime: Date?
    var endTime: Date?
    var isDone: Bool
    /// `true` when the task has a calendar focus block (`manualScheduleGoogleEventId`).
    var isCalendarScheduled: Bool

    init(
        title: String,
        startTime: Date?,
        endTime: Date?,
        isDone: Bool,
        isCalendarScheduled: Bool
    ) {
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.isDone = isDone
        self.isCalendarScheduled = isCalendarScheduled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        startTime = try container.decodeIfPresent(Date.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
        isDone = try container.decode(Bool.self, forKey: .isDone)
        isCalendarScheduled = try container.decodeIfPresent(Bool.self, forKey: .isCalendarScheduled)
            ?? (startTime != nil)
    }
}

struct ShieldSnapshot: Codable {
    var dayKey: String
    var hasPlannedDay: Bool
    /// When `false`, apps are not blocked (e.g. all Today work finished for the day).
    var shouldBlockApps: Bool
    var scheduledTasks: [ScheduledTaskBrief]
    var completedCount: Int
    var totalScheduledCount: Int
    var penaltyAmount: Int
    var updatedAt: Date

    init(
        dayKey: String,
        hasPlannedDay: Bool,
        shouldBlockApps: Bool,
        scheduledTasks: [ScheduledTaskBrief],
        completedCount: Int,
        totalScheduledCount: Int,
        penaltyAmount: Int,
        updatedAt: Date
    ) {
        self.dayKey = dayKey
        self.hasPlannedDay = hasPlannedDay
        self.shouldBlockApps = shouldBlockApps
        self.scheduledTasks = scheduledTasks
        self.completedCount = completedCount
        self.totalScheduledCount = totalScheduledCount
        self.penaltyAmount = penaltyAmount
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dayKey = try container.decode(String.self, forKey: .dayKey)
        hasPlannedDay = try container.decode(Bool.self, forKey: .hasPlannedDay)
        scheduledTasks = try container.decode([ScheduledTaskBrief].self, forKey: .scheduledTasks)
        completedCount = try container.decode(Int.self, forKey: .completedCount)
        totalScheduledCount = try container.decode(Int.self, forKey: .totalScheduledCount)
        penaltyAmount = try container.decode(Int.self, forKey: .penaltyAmount)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        let openCount = scheduledTasks.filter { !$0.isDone }.count
        shouldBlockApps = try container.decodeIfPresent(Bool.self, forKey: .shouldBlockApps)
            ?? (openCount > 0)
    }

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
            guard task.isCalendarScheduled,
                  !task.isDone,
                  let start = task.startTime,
                  let end = task.endTime else { return false }
            return start <= date && date < end
        }
    }

    var openTodayTasks: [ScheduledTaskBrief] {
        scheduledTasks.filter { !$0.isDone }
    }

    func isInTaskSlot(at date: Date = Date()) -> Bool {
        !activeTasks(at: date).isEmpty
    }
}

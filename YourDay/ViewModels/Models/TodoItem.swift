//
//  TodoItem.swift
//  YourDay
//
//  Created by Ruthwika Gajjala on 4/17/25.
//

import Foundation
import SwiftData

enum TaskOrigin: String, Codable {
    case today
    case master
}

@Model
class TodoItem {
    var localTaskId: String = UUID().uuidString
    var title: String
    var detail: String
    var dueDate: Date
    var isDone: Bool
    var subtasks: [Subtask] = []
    var completedAt: Date? = nil
    var origin: TaskOrigin = TaskOrigin.today
    var position: Int = 0
    var sharedTaskId: String? = nil
    var isSharedPending: Bool = false
    var proofPostId: String? = nil
    /// Google Calendar event id for the block created/updated via Manual Scheduling (move instead of duplicate).
    var manualScheduleGoogleEventId: String? = nil
    /// Start time of the scheduled calendar block; mirrors the Google Calendar event so the shield extension can detect active focus windows without network/cache.
    var scheduledStartTime: Date? = nil
    /// End time of the scheduled calendar block.
    var scheduledEndTime: Date? = nil

    init(localTaskId: String = UUID().uuidString, title: String, detail: String, dueDate: Date, isDone: Bool = false, subtasks: [Subtask] = [], position: Int = 0, origin: TaskOrigin = TaskOrigin.today, sharedTaskId: String? = nil, isSharedPending: Bool = false, proofPostId: String? = nil, manualScheduleGoogleEventId: String? = nil, scheduledStartTime: Date? = nil, scheduledEndTime: Date? = nil) {
        self.localTaskId = localTaskId
        self.title = title
        self.detail = detail
        self.dueDate = dueDate
        self.isDone = isDone
        self.subtasks = subtasks
        self.position = position
        self.origin = origin
        self.sharedTaskId = sharedTaskId
        self.isSharedPending = isSharedPending
        self.proofPostId = proofPostId
        self.manualScheduleGoogleEventId = manualScheduleGoogleEventId
        self.scheduledStartTime = scheduledStartTime
        self.scheduledEndTime = scheduledEndTime
    }
}

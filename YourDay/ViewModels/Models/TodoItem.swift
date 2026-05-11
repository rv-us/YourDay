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

/// A concrete location (with resolved coordinates) attached to a task for geofencing.
struct TaskLocation: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var latitude: Double
    var longitude: Double
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
    /// Trello card mirrored into YourDay. Non-nil means task edits should sync back to Trello.
    var trelloCardId: String? = nil
    var trelloBoardId: String? = nil
    var trelloListId: String? = nil
    var trelloDateLastActivity: Date? = nil
    /// When the task was originally created. Used to surface stale tasks during day planning.
    var createdAt: Date = Date()
    /// True once the user has manually dragged this task to a specific spot in the list. Pinned tasks sort by `position` and rank above the auto-sorted (scheduled / unscheduled) groups.
    var userPinned: Bool = false
    /// Primary location category from LLM classification (for display and AI context).
    var locationCategory: String? = nil
    /// Resolved geofence locations for this task. Each entry has concrete coordinates.
    /// Populated by LLM classification (via MKLocalSearch or user-defined places) or manual user selection.
    var taskLocations: [TaskLocation] = []

    init(localTaskId: String = UUID().uuidString, title: String, detail: String, dueDate: Date, isDone: Bool = false, subtasks: [Subtask] = [], position: Int = 0, origin: TaskOrigin = TaskOrigin.today, sharedTaskId: String? = nil, isSharedPending: Bool = false, proofPostId: String? = nil, manualScheduleGoogleEventId: String? = nil, scheduledStartTime: Date? = nil, scheduledEndTime: Date? = nil, trelloCardId: String? = nil, trelloBoardId: String? = nil, trelloListId: String? = nil, trelloDateLastActivity: Date? = nil, createdAt: Date = Date(), userPinned: Bool = false) {
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
        self.trelloCardId = trelloCardId
        self.trelloBoardId = trelloBoardId
        self.trelloListId = trelloListId
        self.trelloDateLastActivity = trelloDateLastActivity
        self.createdAt = createdAt
        self.userPinned = userPinned
    }
}

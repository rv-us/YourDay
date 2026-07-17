//
//  TodoItemCodable.swift
//  YourDay
//
//  Created by Claude on 2/13/26.
//

import Foundation

/// Codable bridge for TodoItem, used for Firebase Firestore serialization.
/// Follows the same pattern as PlayerStatsCodable.
struct TodoItemCodable: Codable, Identifiable {
    var id: String { localTaskId }

    var localTaskId: String
    var title: String
    var detail: String
    var dueDate: Date
    var isDone: Bool
    var subtasks: [SubtaskCodable]
    var completedAt: Date?
    var origin: String // TaskOrigin raw value
    var position: Int
    var sharedTaskId: String?
    var isSharedPending: Bool
    var proofPostId: String?
    var manualScheduleGoogleEventId: String?
    var scheduledStartTime: Date?
    var scheduledEndTime: Date?
    var trelloCardId: String?
    var trelloBoardId: String?
    var trelloListId: String?
    var trelloDateLastActivity: Date?
    var userPinned: Bool
    var groupTaskId: String?
    var groupId: String?
    var groupName: String?

    // Firebase metadata
    var userId: String
    var createdAt: Date
    var updatedAt: Date
    var schemaVersion: Int = 1

    // MARK: - Initializers

    /// Initialize from a SwiftData TodoItem model
    init(from model: TodoItem, userId: String) {
        self.localTaskId = model.localTaskId
        self.title = model.title
        self.detail = model.detail
        self.dueDate = model.dueDate
        self.isDone = model.isDone
        self.subtasks = model.subtasks.map { SubtaskCodable(from: $0) }
        self.completedAt = model.completedAt
        self.origin = model.origin.rawValue
        self.position = model.position
        self.sharedTaskId = model.sharedTaskId
        self.isSharedPending = model.isSharedPending
        self.proofPostId = model.proofPostId
        self.manualScheduleGoogleEventId = model.manualScheduleGoogleEventId
        self.scheduledStartTime = model.scheduledStartTime
        self.scheduledEndTime = model.scheduledEndTime
        self.trelloCardId = model.trelloCardId
        self.trelloBoardId = model.trelloBoardId
        self.trelloListId = model.trelloListId
        self.trelloDateLastActivity = model.trelloDateLastActivity
        self.userPinned = model.userPinned
        self.groupTaskId = model.groupTaskId
        self.groupId = model.groupId
        self.groupName = model.groupName

        self.userId = userId
        self.createdAt = model.createdAt
        self.updatedAt = Date()
        self.schemaVersion = 1
    }

    /// Default initializer for creating new items
    init(
        localTaskId: String = UUID().uuidString,
        title: String,
        detail: String = "",
        dueDate: Date,
        isDone: Bool = false,
        subtasks: [SubtaskCodable] = [],
        completedAt: Date? = nil,
        origin: String = TaskOrigin.today.rawValue,
        position: Int = 0,
        sharedTaskId: String? = nil,
        isSharedPending: Bool = false,
        proofPostId: String? = nil,
        manualScheduleGoogleEventId: String? = nil,
        scheduledStartTime: Date? = nil,
        scheduledEndTime: Date? = nil,
        trelloCardId: String? = nil,
        trelloBoardId: String? = nil,
        trelloListId: String? = nil,
        trelloDateLastActivity: Date? = nil,
        userPinned: Bool = false,
        groupTaskId: String? = nil,
        groupId: String? = nil,
        groupName: String? = nil,
        userId: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        schemaVersion: Int = 1
    ) {
        self.localTaskId = localTaskId
        self.title = title
        self.detail = detail
        self.dueDate = dueDate
        self.isDone = isDone
        self.subtasks = subtasks
        self.completedAt = completedAt
        self.origin = origin
        self.position = position
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
        self.userPinned = userPinned
        self.groupTaskId = groupTaskId
        self.groupId = groupId
        self.groupName = groupName
        self.userId = userId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.schemaVersion = schemaVersion
    }

    // MARK: - Custom Decoding for Schema Migration

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try to decode schema version, default to 1 if not present
        let version = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1

        localTaskId = try container.decode(String.self, forKey: .localTaskId)
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        dueDate = try container.decode(Date.self, forKey: .dueDate)
        isDone = try container.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        subtasks = try container.decodeIfPresent([SubtaskCodable].self, forKey: .subtasks) ?? []
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        origin = try container.decodeIfPresent(String.self, forKey: .origin) ?? TaskOrigin.today.rawValue
        position = try container.decodeIfPresent(Int.self, forKey: .position) ?? 0
        sharedTaskId = try container.decodeIfPresent(String.self, forKey: .sharedTaskId)
        isSharedPending = try container.decodeIfPresent(Bool.self, forKey: .isSharedPending) ?? false
        proofPostId = try container.decodeIfPresent(String.self, forKey: .proofPostId)
        manualScheduleGoogleEventId = try container.decodeIfPresent(String.self, forKey: .manualScheduleGoogleEventId)
        scheduledStartTime = try container.decodeIfPresent(Date.self, forKey: .scheduledStartTime)
        scheduledEndTime = try container.decodeIfPresent(Date.self, forKey: .scheduledEndTime)
        trelloCardId = try container.decodeIfPresent(String.self, forKey: .trelloCardId)
        trelloBoardId = try container.decodeIfPresent(String.self, forKey: .trelloBoardId)
        trelloListId = try container.decodeIfPresent(String.self, forKey: .trelloListId)
        trelloDateLastActivity = try container.decodeIfPresent(Date.self, forKey: .trelloDateLastActivity)
        userPinned = try container.decodeIfPresent(Bool.self, forKey: .userPinned) ?? false
        groupTaskId = try container.decodeIfPresent(String.self, forKey: .groupTaskId)
        groupId = try container.decodeIfPresent(String.self, forKey: .groupId)
        groupName = try container.decodeIfPresent(String.self, forKey: .groupName)

        userId = try container.decode(String.self, forKey: .userId)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()

        // Apply schema migrations if needed
        if version < 1 {
            // Future migrations can be added here
        }

        schemaVersion = 1
    }

    // MARK: - Custom Encoding

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(localTaskId, forKey: .localTaskId)
        try container.encode(title, forKey: .title)
        try container.encode(detail, forKey: .detail)
        try container.encode(dueDate, forKey: .dueDate)
        try container.encode(isDone, forKey: .isDone)
        try container.encode(subtasks, forKey: .subtasks)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encode(origin, forKey: .origin)
        try container.encode(position, forKey: .position)
        try container.encodeIfPresent(sharedTaskId, forKey: .sharedTaskId)
        try container.encode(isSharedPending, forKey: .isSharedPending)
        try container.encodeIfPresent(proofPostId, forKey: .proofPostId)
        try container.encodeIfPresent(manualScheduleGoogleEventId, forKey: .manualScheduleGoogleEventId)
        try container.encodeIfPresent(scheduledStartTime, forKey: .scheduledStartTime)
        try container.encodeIfPresent(scheduledEndTime, forKey: .scheduledEndTime)
        try container.encodeIfPresent(trelloCardId, forKey: .trelloCardId)
        try container.encodeIfPresent(trelloBoardId, forKey: .trelloBoardId)
        try container.encodeIfPresent(trelloListId, forKey: .trelloListId)
        try container.encodeIfPresent(trelloDateLastActivity, forKey: .trelloDateLastActivity)
        try container.encode(userPinned, forKey: .userPinned)
        try container.encodeIfPresent(groupTaskId, forKey: .groupTaskId)
        try container.encodeIfPresent(groupId, forKey: .groupId)
        try container.encodeIfPresent(groupName, forKey: .groupName)
        try container.encode(userId, forKey: .userId)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(schemaVersion, forKey: .schemaVersion)
    }

    private enum CodingKeys: String, CodingKey {
        case localTaskId, title, detail, dueDate, isDone, subtasks, completedAt
        case origin, position, sharedTaskId, isSharedPending, proofPostId, manualScheduleGoogleEventId
        case scheduledStartTime, scheduledEndTime, trelloCardId, trelloBoardId, trelloListId, trelloDateLastActivity, userPinned
        case groupTaskId, groupId, groupName
        case userId, createdAt, updatedAt, schemaVersion
    }

    // MARK: - Convert Back to TodoItem Properties

    /// Returns a tuple of properties to create or update a TodoItem
    func toTodoItemProperties() -> (
        localTaskId: String,
        title: String,
        detail: String,
        dueDate: Date,
        isDone: Bool,
        subtasks: [Subtask],
        completedAt: Date?,
        origin: TaskOrigin,
        position: Int,
        sharedTaskId: String?,
        isSharedPending: Bool,
        proofPostId: String?,
        manualScheduleGoogleEventId: String?,
        scheduledStartTime: Date?,
        scheduledEndTime: Date?,
        trelloCardId: String?,
        trelloBoardId: String?,
        trelloListId: String?,
        trelloDateLastActivity: Date?,
        createdAt: Date,
        userPinned: Bool,
        groupTaskId: String?,
        groupId: String?,
        groupName: String?
    ) {
        return (
            localTaskId: self.localTaskId,
            title: self.title,
            detail: self.detail,
            dueDate: self.dueDate,
            isDone: self.isDone,
            subtasks: self.subtasks.map { $0.toSubtask() },
            completedAt: self.completedAt,
            origin: TaskOrigin(rawValue: self.origin) ?? .today,
            position: self.position,
            sharedTaskId: self.sharedTaskId,
            isSharedPending: self.isSharedPending,
            proofPostId: self.proofPostId,
            manualScheduleGoogleEventId: self.manualScheduleGoogleEventId,
            scheduledStartTime: self.scheduledStartTime,
            scheduledEndTime: self.scheduledEndTime,
            trelloCardId: self.trelloCardId,
            trelloBoardId: self.trelloBoardId,
            trelloListId: self.trelloListId,
            trelloDateLastActivity: self.trelloDateLastActivity,
            createdAt: self.createdAt,
            userPinned: self.userPinned,
            groupTaskId: self.groupTaskId,
            groupId: self.groupId,
            groupName: self.groupName
        )
    }
}

// MARK: - SubtaskCodable

/// Codable wrapper for Subtask (Subtask is already Codable, but wrapping for consistency)
struct SubtaskCodable: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var isDone: Bool
    var completedAt: Date?

    init(from subtask: Subtask) {
        self.id = subtask.id
        self.title = subtask.title
        self.isDone = subtask.isDone
        self.completedAt = subtask.completedAt
    }

    init(id: UUID = UUID(), title: String, isDone: Bool = false, completedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.completedAt = completedAt
    }

    func toSubtask() -> Subtask {
        var subtask = Subtask(id: self.id, title: self.title, isDone: self.isDone)
        subtask.completedAt = self.completedAt
        return subtask
    }
}

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

        self.userId = userId
        self.createdAt = Date()
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
        try container.encode(userId, forKey: .userId)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(schemaVersion, forKey: .schemaVersion)
    }

    private enum CodingKeys: String, CodingKey {
        case localTaskId, title, detail, dueDate, isDone, subtasks, completedAt
        case origin, position, sharedTaskId, isSharedPending, proofPostId, manualScheduleGoogleEventId
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
        manualScheduleGoogleEventId: String?
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
            manualScheduleGoogleEventId: self.manualScheduleGoogleEventId
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

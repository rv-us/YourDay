//
//  NoteItemCodable.swift
//  YourDay
//
//  Created by Claude on 2/13/26.
//

import Foundation

/// Codable bridge for NoteItem, used for Firebase Firestore serialization.
/// Follows the same pattern as PlayerStatsCodable.
struct NoteItemCodable: Codable, Identifiable {
    var id: String { localNoteId }

    var localNoteId: String
    var content: String
    var createdAt: Date

    // Firebase metadata
    var userId: String
    var updatedAt: Date
    var schemaVersion: Int = 1

    // MARK: - Initializers

    /// Initialize from a SwiftData NoteItem model
    init(from model: NoteItem, userId: String) {
        self.localNoteId = model.id.uuidString
        self.content = model.content
        self.createdAt = model.createdAt

        self.userId = userId
        self.updatedAt = Date()
        self.schemaVersion = 1
    }

    /// Default initializer for creating new items
    init(
        localNoteId: String = UUID().uuidString,
        content: String,
        createdAt: Date = Date(),
        userId: String,
        updatedAt: Date = Date(),
        schemaVersion: Int = 1
    ) {
        self.localNoteId = localNoteId
        self.content = content
        self.createdAt = createdAt
        self.userId = userId
        self.updatedAt = updatedAt
        self.schemaVersion = schemaVersion
    }

    // MARK: - Custom Decoding for Schema Migration

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try to decode schema version, default to 1 if not present
        let version = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1

        localNoteId = try container.decode(String.self, forKey: .localNoteId)
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()

        userId = try container.decode(String.self, forKey: .userId)
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

        try container.encode(localNoteId, forKey: .localNoteId)
        try container.encode(content, forKey: .content)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(userId, forKey: .userId)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(schemaVersion, forKey: .schemaVersion)
    }

    private enum CodingKeys: String, CodingKey {
        case localNoteId, content, createdAt
        case userId, updatedAt, schemaVersion
    }

    // MARK: - Convert Back to NoteItem Properties

    /// Returns a tuple of properties to create or update a NoteItem
    func toNoteItemProperties() -> (
        id: UUID,
        content: String,
        createdAt: Date
    ) {
        return (
            id: UUID(uuidString: self.localNoteId) ?? UUID(),
            content: self.content,
            createdAt: self.createdAt
        )
    }
}

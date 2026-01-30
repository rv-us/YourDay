//
//  BacklogItem.swift
//  YourDay
//
//  Model for storing backlog tasks in Firebase
//

import Foundation
import FirebaseFirestore

struct BacklogItem: Identifiable, Codable {
    @DocumentID var id: String?
    let title: String
    let description: String
    let createdAt: Date
    let userId: String
    var priority: Int // Higher number = higher priority
    var estimatedDuration: Int? // Estimated duration in minutes (optional)
    var category: String? // Category for task grouping (e.g., "work", "personal", "health")
    var tags: [String]? // Flexible tags for matching similar tasks

    init(id: String? = nil, title: String, description: String, createdAt: Date = Date(), userId: String, priority: Int = 0, estimatedDuration: Int? = nil, category: String? = nil, tags: [String]? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.createdAt = createdAt
        self.userId = userId
        self.priority = priority
        self.estimatedDuration = estimatedDuration
        self.category = category
        self.tags = tags
    }
}


//
//  SchedulingMessage.swift
//  YourDay
//
//  Model for scheduling chat messages
//

import Foundation
import FirebaseFirestore

enum MessageRole: String, Codable {
    case user
    case assistant
}

struct SchedulingMessage: Identifiable, Codable {
    @DocumentID var id: String?
    let userId: String
    let role: MessageRole
    let content: String
    let timestamp: Date
    var proposedTime: Date? // Optional proposed working session time
    var sessionContext: String? // Optional context about the session being discussed
    
    init(id: String? = nil, userId: String, role: MessageRole, content: String, timestamp: Date = Date(), proposedTime: Date? = nil, sessionContext: String? = nil) {
        self.id = id
        self.userId = userId
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.proposedTime = proposedTime
        self.sessionContext = sessionContext
    }
}


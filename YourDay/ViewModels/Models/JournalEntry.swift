//
//  JournalEntry.swift
//  YourDay
//
//  Model for journal entries after task completion
//

import Foundation
import FirebaseFirestore

enum CompletionStatus: String, Codable {
    case completed
    case partial
    case notStarted
}

struct JournalEntry: Identifiable, Codable {
    @DocumentID var id: String?
    let userId: String
    let eventId: String? // Google Calendar event ID
    let taskTitle: String
    let scheduledStartTime: Date
    let scheduledEndTime: Date
    let actualStartTime: Date?
    let actualEndTime: Date?
    let whatDid: String // Required - what they did
    let howWent: String? // Optional - satisfaction, challenges
    let learned: String? // Optional - insights
    let distractions: String? // Optional - distractions/interruptions
    let completionStatus: CompletionStatus
    let timestamp: Date
    let dayOfWeek: String
    
    init(
        id: String? = nil,
        userId: String,
        eventId: String? = nil,
        taskTitle: String,
        scheduledStartTime: Date,
        scheduledEndTime: Date,
        actualStartTime: Date? = nil,
        actualEndTime: Date? = nil,
        whatDid: String,
        howWent: String? = nil,
        learned: String? = nil,
        distractions: String? = nil,
        completionStatus: CompletionStatus,
        timestamp: Date = Date(),
        dayOfWeek: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.eventId = eventId
        self.taskTitle = taskTitle
        self.scheduledStartTime = scheduledStartTime
        self.scheduledEndTime = scheduledEndTime
        self.actualStartTime = actualStartTime
        self.actualEndTime = actualEndTime
        self.whatDid = whatDid
        self.howWent = howWent
        self.learned = learned
        self.distractions = distractions
        self.completionStatus = completionStatus
        self.timestamp = timestamp
        
        // Auto-calculate dayOfWeek if not provided
        if let dayOfWeek = dayOfWeek {
            self.dayOfWeek = dayOfWeek
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            self.dayOfWeek = formatter.string(from: scheduledStartTime).lowercased()
        }
    }
}



//
//  UserSchedulePreference.swift
//  YourDay
//
//  Model for storing learned schedule preferences
//

import Foundation
import FirebaseFirestore

struct RecurringCommitment: Codable {
    let eventName: String
    let daysOfWeek: [String] // e.g., ["MO", "WE", "FR"]
    let time: String // e.g., "10:00"
    let frequency: String // e.g., "WEEKLY"
}

struct ScheduleConstraint: Codable {
    let reason: String // e.g., "I'm eating lunch", "I normally get up at 9 am"
    let timeRange: String? // e.g., "12:00-13:00" or "before 09:00"
    let context: String? // Additional context about the constraint
}

// MARK: - Time Block
struct TimeBlock: Codable, Equatable {
    let startTime: String  // "09:00"
    let endTime: String    // "12:00"
    let label: String?

    init(startTime: String, endTime: String, label: String? = nil) {
        self.startTime = startTime
        self.endTime = endTime
        self.label = label
    }
}

// MARK: - Day Context (Mon-Sun specific settings)
struct DayContext: Codable {
    let dayOfWeek: String  // "monday", "tuesday", etc.
    var wakeTime: String?  // Override for this day
    var lunchTime: String?
    var generalActivities: [String]  // "gym morning", "errands afternoon"
    var preferredWorkBlocks: [TimeBlock]
    var blockedBlocks: [TimeBlock]

    init(dayOfWeek: String, wakeTime: String? = nil, lunchTime: String? = nil, generalActivities: [String] = [], preferredWorkBlocks: [TimeBlock] = [], blockedBlocks: [TimeBlock] = []) {
        self.dayOfWeek = dayOfWeek
        self.wakeTime = wakeTime
        self.lunchTime = lunchTime
        self.generalActivities = generalActivities
        self.preferredWorkBlocks = preferredWorkBlocks
        self.blockedBlocks = blockedBlocks
    }
}

// MARK: - Schedule Note (one-off notes for specific dates)
struct ScheduleNote: Codable, Identifiable {
    @DocumentID var id: String?
    let date: Date
    let note: String  // "meeting with friend"
    let timeRange: String?  // "14:00-16:00"
    let isBlocking: Bool

    init(id: String? = nil, date: Date, note: String, timeRange: String? = nil, isBlocking: Bool = true) {
        self.id = id
        self.date = date
        self.note = note
        self.timeRange = timeRange
        self.isBlocking = isBlocking
    }
}

// MARK: - Proposal Action
enum ProposalAction: String, Codable {
    case accepted
    case acceptedWithChanges
    case declined
    case skipped
}

// MARK: - Proposal Interaction (track all user interactions for learning)
struct ProposalInteraction: Codable, Identifiable {
    @DocumentID var id: String?
    let timestamp: Date
    let proposedTasks: [String]
    let proposedTime: String
    let proposedDuration: Int  // minutes
    let action: ProposalAction
    let modifiedTime: String?
    let modifiedDuration: Int?
    let declineReason: String?
    let dayOfWeek: String

    init(id: String? = nil, timestamp: Date = Date(), proposedTasks: [String], proposedTime: String, proposedDuration: Int, action: ProposalAction, modifiedTime: String? = nil, modifiedDuration: Int? = nil, declineReason: String? = nil, dayOfWeek: String) {
        self.id = id
        self.timestamp = timestamp
        self.proposedTasks = proposedTasks
        self.proposedTime = proposedTime
        self.proposedDuration = proposedDuration
        self.action = action
        self.modifiedTime = modifiedTime
        self.modifiedDuration = modifiedDuration
        self.declineReason = declineReason
        self.dayOfWeek = dayOfWeek
    }
}

// MARK: - Acceptance Stats (aggregated learning data)
struct AcceptanceStats: Codable {
    var totalAccepted: Int
    var totalDeclined: Int
    var totalModified: Int
    var totalSkipped: Int
    var preferredHours: [Int: Int]  // hour -> count (which hours user tends to accept)
    var preferredDurations: [Int: Int]  // duration -> count (which durations user tends to accept)
    var averageAcceptedDuration: Int?  // average duration of accepted sessions

    init(totalAccepted: Int = 0, totalDeclined: Int = 0, totalModified: Int = 0, totalSkipped: Int = 0, preferredHours: [Int: Int] = [:], preferredDurations: [Int: Int] = [:], averageAcceptedDuration: Int? = nil) {
        self.totalAccepted = totalAccepted
        self.totalDeclined = totalDeclined
        self.totalModified = totalModified
        self.totalSkipped = totalSkipped
        self.preferredHours = preferredHours
        self.preferredDurations = preferredDurations
        self.averageAcceptedDuration = averageAcceptedDuration
    }
}

struct UserSchedulePreference: Codable {
    @DocumentID var id: String?
    let userId: String
    var preferredWakeTime: String? // e.g., "09:00"
    var lunchTime: String? // e.g., "12:30"
    var preferredWorkTimes: [String]? // Array of preferred time ranges
    var blockedTimes: [String]? // Array of blocked time ranges
    var learnedPatterns: [String: String]? // Key-value pairs of learned patterns
    var scheduleConstraints: [ScheduleConstraint] = [] // General constraints learned from user feedback
    var recurringCommitments: [RecurringCommitment] = []
    var dayContexts: [String: DayContext]? // Day-specific contexts keyed by day name (monday, tuesday, etc.)
    var acceptanceStats: AcceptanceStats? // Aggregated stats for learning

    init(id: String? = nil, userId: String, preferredWakeTime: String? = nil, lunchTime: String? = nil, preferredWorkTimes: [String]? = nil, blockedTimes: [String]? = nil, learnedPatterns: [String: String]? = nil, scheduleConstraints: [ScheduleConstraint] = [], recurringCommitments: [RecurringCommitment] = [], dayContexts: [String: DayContext]? = nil, acceptanceStats: AcceptanceStats? = nil) {
        self.id = id
        self.userId = userId
        self.preferredWakeTime = preferredWakeTime
        self.lunchTime = lunchTime
        self.preferredWorkTimes = preferredWorkTimes
        self.blockedTimes = blockedTimes
        self.learnedPatterns = learnedPatterns
        self.scheduleConstraints = scheduleConstraints
        self.recurringCommitments = recurringCommitments
        self.dayContexts = dayContexts
        self.acceptanceStats = acceptanceStats
    }
}


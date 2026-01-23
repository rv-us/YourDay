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
    
    init(id: String? = nil, userId: String, preferredWakeTime: String? = nil, lunchTime: String? = nil, preferredWorkTimes: [String]? = nil, blockedTimes: [String]? = nil, learnedPatterns: [String: String]? = nil, scheduleConstraints: [ScheduleConstraint] = [], recurringCommitments: [RecurringCommitment] = []) {
        self.id = id
        self.userId = userId
        self.preferredWakeTime = preferredWakeTime
        self.lunchTime = lunchTime
        self.preferredWorkTimes = preferredWorkTimes
        self.blockedTimes = blockedTimes
        self.learnedPatterns = learnedPatterns
        self.scheduleConstraints = scheduleConstraints
        self.recurringCommitments = recurringCommitments
    }
}

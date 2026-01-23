//
//  ProposedSession.swift
//  YourDay
//
//  Model for proposed working sessions
//

import Foundation

struct ProposedSession: Codable {
    let tasks: [String] // Can be single task or multiple grouped tasks
    let workingSessionTime: String // e.g., "2:00 PM - 3:30 PM"
    let startTime: Date? // Parsed start time
    let endTime: Date? // Parsed end time
    let reason: String? // Why this time was chosen
    
    // Convenience property for single task
    var task: String {
        tasks.first ?? ""
    }
}

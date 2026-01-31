//
//  ProposedSession.swift
//  YourDay
//
//  Model for proposed working sessions
//

import Foundation

// MARK: - Task Grouping Type
enum TaskGroupingType: String, Codable {
    case quickTaskBatch  // Multiple quick tasks (<15 min each) batched together
    case relatedTasks    // Tasks grouped by category/similarity
    case singleFocus     // Single task requiring focused attention
}

// MARK: - Proposed Task Detail
struct ProposedTaskDetail: Codable {
    let title: String
    let estimatedDuration: Int?  // minutes
    let priority: Int

    init(title: String, estimatedDuration: Int? = nil, priority: Int = 0) {
        self.title = title
        self.estimatedDuration = estimatedDuration
        self.priority = priority
    }
}

struct ProposedSession: Codable {
    var tasks: [String] // Can be single task or multiple grouped tasks (mutable for user edits)
    let workingSessionTime: String // e.g., "2:00 PM - 3:30 PM"
    var startTime: Date? // Parsed start time
    var endTime: Date? // Parsed end time
    let reason: String? // Why this time was chosen

    // NEW: Task metadata for detailed display
    var taskDetails: [ProposedTaskDetail]?

    // NEW: User adjustments
    var adjustedStartTime: Date?
    var adjustedDuration: Int?  // minutes

    // NEW: Grouping rationale
    var groupingType: TaskGroupingType?

    // Convenience property for single task
    var task: String {
        tasks.first ?? ""
    }

    // Computed property for effective start time (adjusted or original)
    var effectiveStartTime: Date? {
        adjustedStartTime ?? startTime
    }

    // Computed property for effective duration in minutes
    var effectiveDuration: Int? {
        if let adjusted = adjustedDuration {
            return max(15, adjusted)  // Ensure minimum 15 minutes
        }
        guard let start = startTime, let end = endTime else { return nil }
        let duration = Int(end.timeIntervalSince(start) / 60)
        // Handle negative duration (e.g., if times cross midnight) by returning a sensible default
        return duration > 0 ? duration : 60
    }

    // Computed property for effective end time
    var effectiveEndTime: Date? {
        guard let start = effectiveStartTime else { return nil }
        if let duration = adjustedDuration {
            return Calendar.current.date(byAdding: .minute, value: duration, to: start)
        }
        return endTime
    }

    // Check if user has made modifications
    var hasModifications: Bool {
        adjustedStartTime != nil || adjustedDuration != nil
    }

    // Format the effective time range as a string
    var effectiveTimeString: String {
        guard let start = effectiveStartTime, let end = effectiveEndTime else {
            return workingSessionTime
        }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
}


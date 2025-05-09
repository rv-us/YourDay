//
//  DailySummaryTask.swift
//  YourDay
//
//  Created by Rachit Verma on 5/7/25.
//
import Foundation
import SwiftData

@Model
class DailySummaryTask {
    var id: UUID
    var taskTitle: String
    var date: Date
    var totalPoints: Double // Points earned for this task on this date
    var subtaskTitles: [String]
    var subtaskPoints: [Double]
    var mainTaskCompleted: Bool
    var taskMaxPossiblePoints: Double // The base/max points this task could have earned on this date

    init(
        taskTitle: String,
        date: Date,
        totalPoints: Double,
        subtaskTitles: [String],
        subtaskPoints: [Double],
        mainTaskCompleted: Bool,
        taskMaxPossiblePoints: Double // New parameter
    ) {
        self.id = UUID()
        self.taskTitle = taskTitle
        self.date = date
        self.totalPoints = totalPoints
        self.subtaskTitles = subtaskTitles
        self.subtaskPoints = subtaskPoints
        self.mainTaskCompleted = mainTaskCompleted
        self.taskMaxPossiblePoints = taskMaxPossiblePoints // Assign new property
    }
}

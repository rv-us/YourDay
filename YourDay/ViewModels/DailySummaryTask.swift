//
//  Dailysummary.swift
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
    var totalPoints: Double
    var subtaskTitles: [String]
    var subtaskPoints: [Double]

    init(
        taskTitle: String,
        date: Date,
        totalPoints: Double,
        subtaskTitles: [String],
        subtaskPoints: [Double]
    ) {
        self.id = UUID()
        self.taskTitle = taskTitle
        self.date = date
        self.totalPoints = totalPoints
        self.subtaskTitles = subtaskTitles
        self.subtaskPoints = subtaskPoints
    }
}

//
//  TodoItem.swift
//  YourDay
//
//  Created by Ruthwika Gajjala on 4/17/25.
//

import Foundation
import SwiftData

enum TaskOrigin: String, Codable {
    case today
    case master
}

@Model
class TodoItem {
    var title: String
    var detail: String
    var dueDate: Date
    var isDone: Bool
    var subtasks: [Subtask] = []
    var completedAt: Date? = nil
    var origin: TaskOrigin = TaskOrigin.today
    var position: Int = 0
    var sharedTaskId: String? = nil
    var isSharedPending: Bool = false

    init(title: String, detail: String, dueDate: Date, isDone: Bool = false, subtasks: [Subtask] = [], position: Int = 0, origin: TaskOrigin = TaskOrigin.today, sharedTaskId: String? = nil, isSharedPending: Bool = false) {
        self.title = title
        self.detail = detail
        self.dueDate = dueDate
        self.isDone = isDone
        self.subtasks = subtasks
        self.position = position
        self.origin = origin
        self.sharedTaskId = sharedTaskId
        self.isSharedPending = isSharedPending
    }
}


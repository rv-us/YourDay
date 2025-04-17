//
//  TodoItem.swift
//  YourDay
//
//  Created by Ruthwika Gajjala on 4/17/25.
//


import Foundation
import SwiftData

@Model
class TodoItem {
    var title: String
    var detail: String
    var dueDate: Date
    var isDone: Bool

    init(title: String, detail: String, dueDate: Date, isDone: Bool = false) {
        self.title = title
        self.detail = detail
        self.dueDate = dueDate
        self.isDone = isDone
    }
}

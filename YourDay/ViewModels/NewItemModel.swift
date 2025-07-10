//
//  NewItemModel.swift
//  YourDay
//
//  Created by Rachit Verma on 4/16/25.
//
import Foundation

class NewItemModel: ObservableObject {
    @Published var title = ""
    @Published var description = ""
    @Published var donebye = Date()
    @Published var showAlert = false
    @Published var subtasks: [Subtask] = []
    @Published var origin: TaskOrigin = .today

    
    var originalItem: TodoItem? = nil

    init(item: TodoItem? = nil) {
        if let item = item {
            self.originalItem = item
            self.title = item.title
            self.description = item.detail
            self.donebye = item.dueDate
            self.subtasks = item.subtasks
        }
    }

    func addSubtask() {
        subtasks.append(Subtask(title: ""))
    }

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && donebye >= Date().addingTimeInterval(-86400)
    }
}

//
//  NewItemview.swift
//  YourDay
//
//  Created by Rachit Verma on 4/16/25.
//

import SwiftUI
import SwiftData

struct NewItemview: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @StateObject var viewModel: NewItemModel
    @Binding var newItemPresented: Bool

    init(newItemPresented: Binding<Bool>, editingItem: TodoItem? = nil) {
        self._viewModel = StateObject(wrappedValue: NewItemModel(item: editingItem))
        self._newItemPresented = newItemPresented
    }

    var body: some View {
        VStack {
            Text(viewModel.originalItem == nil ? "New Task" : "Edit Task")
                .font(.system(size: 32))
                .bold()
                .padding(.top, 80)

            Form {
                TextField("Task", text: $viewModel.title)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                TextField("Description", text: $viewModel.description)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Section(header: Text("Subtasks")) {
                    ForEach($viewModel.subtasks) { $subtask in
                        HStack {
                            Image(systemName: subtask.isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(subtask.isDone ? .green : .gray)
                            TextField("Subtask", text: $subtask.title)
                        }
                    }
                    Button(action: viewModel.addSubtask) {
                        Label("Add Subtask", systemImage: "plus")
                    }
                }

                DatePicker("Due Date", selection: $viewModel.donebye)
                    .datePickerStyle(GraphicalDatePickerStyle())

                Button(action: {
                    guard viewModel.canSave else {
                        viewModel.showAlert = true
                        return
                    }

                    if let existing = viewModel.originalItem {
                        existing.title = viewModel.title
                        existing.detail = viewModel.description
                        existing.dueDate = viewModel.donebye
                        existing.subtasks = viewModel.subtasks
                        print("Updated task '\(existing.title)'")
                    } else {
                        let newItem = TodoItem(
                            title: viewModel.title,
                            detail: viewModel.description,
                            dueDate: viewModel.donebye,
                            subtasks: viewModel.subtasks
                        )
                        context.insert(newItem)
                        print("Created new task '\(newItem.title)'")
                    }

                    dismiss()
                }) {
                    Text(viewModel.originalItem == nil ? "Add" : "Save")
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding()
            }
            .alert(isPresented: $viewModel.showAlert) {
                Alert(title: Text("Error"), message: Text("Please fill in task field and select a future due date"))
            }
        }
    }
}


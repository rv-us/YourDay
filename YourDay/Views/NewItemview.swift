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
                Text("Description")
                    .font(.caption)
                    .foregroundColor(.gray)
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.5))
                    TextEditor(text: $viewModel.description)
                        .frame(minHeight: 80)
                        .padding(4)
                }


                Section(header: Text("Subtasks")) {
                    ForEach($viewModel.subtasks) { $subtask in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.5))
                            TextEditor(text: $subtask.title)
                                .frame(minHeight: 44)
                                .padding(4)
                        }
                    }
                    .onDelete { indexSet in
                        viewModel.subtasks.remove(atOffsets: indexSet)
                    }

                    Button(action: viewModel.addSubtask) {
                        Label("Add Subtask", systemImage: "plus")
                    }
                }


                DatePicker("Due Date", selection: $viewModel.donebye)
                    .datePickerStyle(GraphicalDatePickerStyle())

                Button(action: {
                    // Skip validation for due date safeguard
                    if viewModel.title.trimmingCharacters(in: .whitespaces).isEmpty {
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
                Alert(title: Text("Error"), message: Text("Please fill in task field"))
            }
        }
    }
}

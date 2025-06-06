////
////  NewItemview.swift
////  YourDay
////
////  Created by Rachit Verma on 4/16/25.
////
//
//import SwiftUI
//import SwiftData
//
//struct NewItemview: View {
//    @Environment(\.modelContext) private var context
//    @Environment(\.dismiss) private var dismiss
//    @StateObject var viewModel: NewItemModel
//    @Binding var newItemPresented: Bool
//
//    init(newItemPresented: Binding<Bool>, editingItem: TodoItem? = nil) {
//        self._viewModel = StateObject(wrappedValue: NewItemModel(item: editingItem))
//        self._newItemPresented = newItemPresented
//    }
//
//    var body: some View {
//        NavigationView {
//            Form {
//                Section(header: Text("Task Details").font(.headline)) {
//                    VStack(alignment: .leading, spacing: 12) {
//                        Text("Title")
//                            .font(.subheadline)
//                            .foregroundColor(.secondary)
//
//                        TextField("Enter task title", text: $viewModel.title)
//                            .padding(10)
//                            .background(Color(.systemGray6))
//                            .cornerRadius(10)
//
//                        Text("Description")
//                            .font(.subheadline)
//                            .foregroundColor(.secondary)
//
//                        TextEditor(text: $viewModel.description)
//                            .frame(minHeight: 100)
//                            .padding(10)
//                            .background(Color(.systemGray6))
//                            .cornerRadius(10)
//                    }
//                    .padding(.vertical, 4)
//                }
//                .padding(.vertical, 15)
//
//                Section(header: Text("Subtasks").font(.headline)) {
//                    ForEach($viewModel.subtasks) { $subtask in
//                        TextField("Subtask", text: $subtask.title)
//                            .padding(8)
//                            .background(Color(.systemGray6))
//                            .cornerRadius(8)
//                    }
//                    .onDelete { indexSet in
//                        viewModel.subtasks.remove(atOffsets: indexSet)
//                    }
//
//                    Button(action: viewModel.addSubtask) {
//                        Label("Add Subtask", systemImage: "plus.circle.fill")
//                            .foregroundColor(.blue)
//                    }
//                }
//
//                Section(header: Text("Due Date").font(.headline)) {
//                    DatePicker("Select Due Date", selection: $viewModel.donebye)
//                        .datePickerStyle(GraphicalDatePickerStyle())
//                }
//
//                Section {
//                    Button(action: saveTask) {
//                        Text(viewModel.originalItem == nil ? "Add" : "Save")
//                            .foregroundColor(.white)
//                            .frame(maxWidth: .infinity)
//                            .padding()
//                            .background(Color.blue)
//                            .cornerRadius(10)
//                    }
//                    .listRowBackground(Color.clear)
//                }
//            }
////            .navigationTitle(viewModel.originalItem == nil ? "New Task" : "Edit Task")
//            .alert(isPresented: $viewModel.showAlert) {
//                Alert(title: Text("Error"), message: Text("Please fill in task field"))
//            }
//        }
//    }
//
//    private func saveTask() {
//        if viewModel.title.trimmingCharacters(in: .whitespaces).isEmpty {
//            viewModel.showAlert = true
//            return
//        }
//
//        if let existing = viewModel.originalItem {
//            existing.title = viewModel.title
//            existing.detail = viewModel.description
//            existing.dueDate = viewModel.donebye
//            existing.subtasks = viewModel.subtasks
//            print("Updated task '\(existing.title)')")
//        } else {
//            let newItem = TodoItem(
//                title: viewModel.title,
//                detail: viewModel.description,
//                dueDate: viewModel.donebye,
//                subtasks: viewModel.subtasks
//            )
//            context.insert(newItem)
//            print("Created new task '\(newItem.title)')")
//        }
//
//        dismiss()
//    }
//}

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
        NavigationView {
            Form {
                Section(header:
                    Text("Task Details")
                        .font(.headline)
                        .foregroundColor(plantDarkGreen)
                        .padding(.top, 5)
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Title")
                            .font(.subheadline)
                            .foregroundColor(plantMediumGreen)

                        TextField("Enter task title", text: $viewModel.title)
                            .padding(10)
                            .background(plantPastelGreen.opacity(0.3))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(plantMediumGreen.opacity(0.5), lineWidth: 1)
                            )
                            .foregroundColor(plantDarkGreen)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.sentences)

                        Text("Description")
                            .font(.subheadline)
                            .foregroundColor(plantMediumGreen)

                        TextEditor(text: $viewModel.description)
                            .frame(minHeight: 100)
                            .padding(10)
                            .background(plantPastelGreen.opacity(0.3))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(plantMediumGreen.opacity(0.5), lineWidth: 1)
                            )
                            .foregroundColor(plantDarkGreen)
                            .textInputAutocapitalization(.sentences)
                            .scrollContentBackground(.hidden)
                    }
                    .listRowBackground(plantBeige)
                }

                Section(header:
                    Text("Subtasks")
                        .font(.headline)
                        .foregroundColor(plantDarkGreen)
                        .padding(.top, 5)
                ) {
                    ForEach($viewModel.subtasks) { $subtask in
                        TextField("Subtask", text: $subtask.title)
                            .padding(8)
                            .background(plantPastelGreen.opacity(0.3))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(plantMediumGreen.opacity(0.5), lineWidth: 1)
                            )
                            .foregroundColor(plantDarkGreen)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.sentences)
                            .listRowBackground(plantBeige)
                    }
                    .onDelete { indexSet in
                        viewModel.subtasks.remove(atOffsets: indexSet)
                    }

                    Button(action: viewModel.addSubtask) {
                        Label("Add Subtask", systemImage: "plus.circle.fill")
                            .foregroundColor(plantDustyBlue)
                    }
                    .listRowBackground(plantBeige)
                }

                Section(header:
                    Text("Due Date")
                        .font(.headline)
                        .foregroundColor(plantDarkGreen)
                        .padding(.top, 5)
                ) {
                    DatePicker("Select Due Date", selection: $viewModel.donebye)
                        .datePickerStyle(GraphicalDatePickerStyle())
                        .tint(plantMediumGreen)
                        .foregroundColor(plantDarkGreen)
                        // --- UPDATED BORDER AND BACKGROUND FOR DATEPICKER ---
                        .background(plantPastelGreen.opacity(0.5)) // Increased opacity for better visibility
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(plantMediumGreen, lineWidth: 1.5) // Increased line width for border
                        )
                        .padding(.vertical, 5)
                        // --- END UPDATED MODIFIERS ---
                        .listRowBackground(plantBeige)
                }

                Section {
                    Button(action: saveTask) {
                        Text(viewModel.originalItem == nil ? "Add Task" : "Save Task")
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? plantDustyBlue.opacity(0.5) : plantMediumGreen)
                            .cornerRadius(10)
                    }
                    .listRowBackground(Color.clear)
                    .disabled(viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .scrollContentBackground(.hidden)
            .background(plantBeige.edgesIgnoringSafeArea(.all))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(plantLightMintGreen, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(plantDarkGreen)
                }
                ToolbarItem(placement: .principal) {
                    Text(viewModel.originalItem == nil ? "New Task" : "Edit Task")
                        .fontWeight(.bold)
                        .foregroundColor(plantDarkGreen)
                }
            }
            .alert(isPresented: $viewModel.showAlert) {
                Alert(title: Text("Error"), message: Text("Please fill in task title"))
            }
        }
        .navigationViewStyle(.stack)
    }

    private func saveTask() {
        if viewModel.title.trimmingCharacters(in: .whitespaces).isEmpty {
            viewModel.showAlert = true
            return
        }

        if let existing = viewModel.originalItem {
            existing.title = viewModel.title
            existing.detail = viewModel.description
            existing.dueDate = viewModel.donebye
            existing.subtasks = viewModel.subtasks
            print("Updated task '\(existing.title)')")
        } else {
            let newItem = TodoItem(
                title: viewModel.title,
                detail: viewModel.description,
                dueDate: viewModel.donebye,
                subtasks: viewModel.subtasks
            )
            context.insert(newItem)
            print("Created new task '\(newItem.title)')")
        }

        dismiss()
    }
}

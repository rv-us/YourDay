////
////  ConfirmGeneratedTasksView.swift
////  YourDay
////
////  Created by Rachit Verma on 4/27/25.
////
////
////  ConfirmGeneratedTasksView.swift
////  YourDay
////
//
//import SwiftUI
//
//struct ConfirmGeneratedTasksView: View {
//    var tasks: [TodoItem]
//    var onConfirm: ([TodoItem]) -> Void
//
//    @State private var selectedTasks: Set<TodoItem> = []
//
//    var body: some View {
//        NavigationView {
//            List {
//                ForEach(tasks) { task in
//                    HStack {
//                        Button(action: {
//                            toggleSelection(for: task)
//                        }) {
//                            Image(systemName: selectedTasks.contains(task) ? "checkmark.square.fill" : "square")
//                        }
//                        .buttonStyle(PlainButtonStyle())
//
//                        VStack(alignment: .leading) {
//                            Text(task.title)
//                                .font(.headline)
//                            if !task.detail.isEmpty {
//                                Text(task.detail)
//                                    .font(.caption)
//                                    .foregroundColor(.gray)
//                            }
//                        }
//                    }
//                    .padding(.vertical, 4)
//                }
//            }
//            .navigationTitle("Confirm Tasks")
//            .toolbar {
//                ToolbarItem(placement: .navigationBarTrailing) {
//                    Button("Add Selected") {
//                        onConfirm(Array(selectedTasks))
//                    }
//                    .disabled(selectedTasks.isEmpty)
//                }
//            }
//        }
//    }
//
//    func toggleSelection(for task: TodoItem) {
//        if selectedTasks.contains(task) {
//            selectedTasks.remove(task)
//        } else {
//            selectedTasks.insert(task)
//        }
//    }
//}
//
//

import SwiftUI

struct ConfirmGeneratedTasksView: View {
    var tasks: [TodoItem]
    var onConfirm: ([TodoItem]) -> Void

    @State private var selectedTasks: Set<TodoItem> = []

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                List {
                    ForEach(tasks) { task in
                        HStack {
                            Button(action: {
                                toggleSelection(for: task)
                            }) {
                                Image(systemName: selectedTasks.contains(task) ? "checkmark.square.fill" : "square")
                                    .foregroundColor(selectedTasks.contains(task) ? dynamicPrimaryColor : dynamicSecondaryTextColor)
                            }
                            .buttonStyle(PlainButtonStyle())

                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.title)
                                    .font(.headline)
                                    .foregroundColor(dynamicTextColor)
                                if !task.detail.isEmpty {
                                    Text(task.detail)
                                        .font(.caption)
                                        .foregroundColor(dynamicSecondaryTextColor)
                                }
                                if !task.subtasks.isEmpty {
                                    VStack(alignment: .leading, spacing: 2) {
                                        ForEach(task.subtasks) { subtask in
                                            HStack(spacing: 6) {
                                                Text("•")
                                                    .font(.caption)
                                                    .foregroundColor(dynamicSecondaryTextColor)
                                                Text(subtask.title)
                                                    .font(.caption)
                                                    .foregroundColor(dynamicSecondaryTextColor)
                                            }
                                        }
                                    }
                                    .padding(.leading, 8)
                                    .padding(.top, 2)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(selectedTasks.contains(task) ? dynamicPrimaryColor.opacity(0.3) : dynamicSecondaryBackgroundColor)
                    }
                }
                .listStyle(.plain)
                .background(dynamicBackgroundColor)
            }
            .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Confirm Tasks")
                        .fontWeight(.bold)
                        .foregroundColor(dynamicTextColor)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add Selected") {
                        onConfirm(Array(selectedTasks))
                    }
                    .foregroundColor(dynamicPrimaryColor)
                    .disabled(selectedTasks.isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            selectedTasks = Set(tasks)
        }
    }

    func toggleSelection(for task: TodoItem) {
        if selectedTasks.contains(task) {
            selectedTasks.remove(task)
        } else {
            selectedTasks.insert(task)
        }
    }
}

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
            VStack(spacing: 0) { // Added VStack with spacing 0 for better background control
                List {
                    ForEach(tasks) { task in
                        HStack {
                            Button(action: {
                                toggleSelection(for: task)
                            }) {
                                Image(systemName: selectedTasks.contains(task) ? "checkmark.square.fill" : "square")
                                    // Themed checkbox icon colors
                                    .foregroundColor(selectedTasks.contains(task) ? plantDarkGreen : plantDustyBlue)
                            }
                            .buttonStyle(PlainButtonStyle())

                            VStack(alignment: .leading) {
                                Text(task.title)
                                    .font(.headline)
                                    .foregroundColor(plantDarkGreen) // Themed title color
                                if !task.detail.isEmpty {
                                    Text(task.detail)
                                        .font(.caption)
                                        .foregroundColor(plantMediumGreen) // Themed detail color
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        // Themed row background for selection
                        .listRowBackground(selectedTasks.contains(task) ? plantPastelGreen.opacity(0.6) : plantBeige)
                    }
                }
                .listStyle(.plain) // Use plain list style for flat look
                .background(plantBeige) // Apply theme background to the list itself
            }
            .background(plantBeige.edgesIgnoringSafeArea(.all)) // Overall view background
            .navigationTitle("") // Hide default title
            .navigationBarTitleDisplayMode(.inline) // Ensure custom title displays correctly
            .toolbarBackground(plantLightMintGreen, for: .navigationBar) // Themed navigation bar background
            .toolbarBackground(.visible, for: .navigationBar) // Make background visible
            .toolbar {
                ToolbarItem(placement: .principal) { // Custom title
                    Text("Confirm Tasks")
                        .fontWeight(.bold)
                        .foregroundColor(plantDarkGreen) // Themed title color
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add Selected") {
                        onConfirm(Array(selectedTasks))
                    }
                    .foregroundColor(plantDarkGreen) // Keep text white as per original, but now with themed background
                    .disabled(selectedTasks.isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack) // Consistent navigation style
        .onAppear {
            // Initially select all tasks for confirmation
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

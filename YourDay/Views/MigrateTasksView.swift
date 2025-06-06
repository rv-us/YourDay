//import SwiftUI
//import SwiftData
//
//struct MigrateTasksView: View {
//    @Environment(\.modelContext) private var modelContext
//    @Environment(\.dismiss) private var dismiss
//
//    // Fetches all TodoItems. Filtering for display is done in tasksToReview.
//    @Query private var allTodoItems: [TodoItem]
//    @State private var selectedTasksToMigrate: Set<PersistentIdentifier> = []
//
//    // tasksToReview shows items that are incomplete OR have incomplete subtasks.
//    // These are the candidates for migration or deletion.
//    private var tasksToReview: [TodoItem] {
//        allTodoItems.filter { todoItem in
//            let isMainTaskIncomplete = !todoItem.isDone
//            let hasIncompleteSubtasks = todoItem.subtasks.contains(where: { !$0.isDone })
//            return isMainTaskIncomplete || hasIncompleteSubtasks
//        }
//    }
//
//    var body: some View {
//        NavigationView {
//            VStack {
//                if tasksToReview.isEmpty {
//                    Spacer()
//                    Text("No tasks need review or migration!")
//                        .font(.title2)
//                        .foregroundColor(.gray)
//                        .multilineTextAlignment(.center)
//                        .padding()
//                    Spacer()
//                } else {
//                    Text("Select tasks to move to today's list:")
//                        .font(.headline)
//                        .padding(.top)
//                    
//                    List {
//                        ForEach(tasksToReview) { task in
//                            HStack {
//                                VStack(alignment: .leading) {
//                                    Text(task.title)
//                                        .font(.headline)
//                                        // Strikethrough if main task is done AND no subtasks are pending
//                                        .strikethrough(task.isDone && !task.subtasks.contains(where: {!$0.isDone}), color: .gray)
//                                    
//                                    if !task.detail.isEmpty {
//                                        Text(task.detail)
//                                            .font(.caption)
//                                            .foregroundColor(.gray)
//                                            .lineLimit(1)
//                                    }
//                                    Text("Original due: \(task.dueDate, style: .date)")
//                                        .font(.caption2)
//                                        .foregroundColor(.orange)
//                                    
//                                    let pendingSubtasks = task.subtasks.filter { !$0.isDone }.count
//                                    if pendingSubtasks > 0 {
//                                        Text("\(pendingSubtasks) subtask(s) pending")
//                                            .font(.caption2)
//                                            .foregroundColor(.purple)
//                                    } else if !task.subtasks.isEmpty && task.isDone {
//                                        Text("All subtasks complete")
//                                            .font(.caption2)
//                                            .foregroundColor(.green)
//                                    }
//                                }
//                                Spacer()
//                                Image(systemName: selectedTasksToMigrate.contains(task.id) ? "checkmark.circle.fill" : "circle")
//                                    .foregroundColor(selectedTasksToMigrate.contains(task.id) ? .blue : .gray)
//                                    .font(.title2)
//                            }
//                            .contentShape(Rectangle())
//                            .onTapGesture {
//                                if selectedTasksToMigrate.contains(task.id) {
//                                    selectedTasksToMigrate.remove(task.id)
//                                } else {
//                                    selectedTasksToMigrate.insert(task.id)
//                                }
//                            }
//                        }
//                    }
//                }
//
//                VStack(spacing: 15) {
//                    if !tasksToReview.isEmpty {
//                        Button {
//                            processTaskSelections()
//                            dismiss()
//                        } label: {
//                            Text("Confirm Selections (\(selectedTasksToMigrate.count) for Today)")
//                                .font(.headline)
//                                .padding()
//                                .frame(maxWidth: .infinity)
//                                .background(Color.blue) // Always enabled if tasksToReview isn't empty
//                                .foregroundColor(.white)
//                                .cornerRadius(10)
//                        }
//                    }
//
//                    // This button is now more of a "discard all remaining unmigrated tasks"
//                    // if the user doesn't want to select any.
//                    // Or it can be removed if the above button handles all cases.
//                    // For simplicity, let's assume the above button is the primary action.
//                    // If no tasks are selected, it means "delete all reviewed tasks".
//                    // If some are selected, it means "migrate selected, delete others".
//                    // So, the "Skip & Delete All Reviewed Tasks" button might be redundant
//                    // or can be rephrased if needed. Let's keep it for now for explicit "discard all".
//                    Button {
//                        if !tasksToReview.isEmpty {
//                             deleteAllReviewedTasks()
//                        }
//                        dismiss()
//                    } label: {
//                        Text(tasksToReview.isEmpty ? "All Clear!" : "Discard All Reviewed Tasks")
//                            .font(.headline)
//                            .padding()
//                            .frame(maxWidth: .infinity)
//                            .background(tasksToReview.isEmpty ? Color.green : Color.red.opacity(0.8))
//                            .foregroundColor(.white)
//                            .cornerRadius(10)
//                    }
//                }
//                .padding()
//            }
//            .navigationTitle("Review Old Tasks")
//            .navigationBarTitleDisplayMode(.inline)
//            .toolbar {
//                ToolbarItem(placement: .cancellationAction) {
//                    Button("Later") { // "Later" button does not delete anything
//                        dismiss()
//                    }
//                }
//            }
//        }
//    }
//
//    private func processTaskSelections() {
//        let today = Calendar.current.startOfDay(for: Date())
//
//        for taskInReview in tasksToReview {
//            if selectedTasksToMigrate.contains(taskInReview.id) {
//                // Task is selected for migration: update its due date and reset isDone
//                taskInReview.dueDate = today
//                taskInReview.isDone = false // Main task is reset to not done for the new day
//                taskInReview.completedAt = nil // Reset completion date
//                // Subtasks' isDone status is preserved as per their original state.
//                // If you wanted to reset subtasks too, you'd iterate and set them to false.
//                print("Migrating task: \(taskInReview.title) to today. Subtask statuses preserved.")
//            } else {
//                // Task was reviewed but NOT selected for migration: delete it
//                print("Deleting unselected task: \(taskInReview.title)")
//                modelContext.delete(taskInReview)
//            }
//        }
//        
//        do {
//            try modelContext.save()
//        } catch {
//            print("Error saving context after processing task selections: \(error.localizedDescription)")
//        }
//    }
//
//    private func deleteAllReviewedTasks() {
//        // This function is for the "Discard All Reviewed Tasks" button
//        for task in tasksToReview {
//            print("Deleting task via 'Discard All': \(task.title)")
//            modelContext.delete(task)
//        }
//        do {
//            try modelContext.save()
//        } catch {
//            print("Error saving context after discarding all reviewed tasks: \(error.localizedDescription)")
//        }
//    }
//}
//

import SwiftUI
import SwiftData

struct MigrateTasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Fetches all TodoItems. Filtering for display is done in tasksToReview.
    @Query private var allTodoItems: [TodoItem]
    @State private var selectedTasksToMigrate: Set<PersistentIdentifier> = []

    // tasksToReview shows items that are incomplete OR have incomplete subtasks.
    // These are the candidates for migration or deletion.
    private var tasksToReview: [TodoItem] {
        allTodoItems.filter { todoItem in
            let isMainTaskIncomplete = !todoItem.isDone
            let hasIncompleteSubtasks = todoItem.subtasks.contains(where: { !$0.isDone })
            return isMainTaskIncomplete || hasIncompleteSubtasks
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) { // Ensures no extra spacing at top/bottom of VStack
                if tasksToReview.isEmpty {
                    Spacer()
                    Text("No tasks need review or migration!")
                        .font(.title2)
                        .foregroundColor(plantDustyBlue) // Themed color
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                } else {
                    Text("Select tasks to move to today's list:")
                        .font(.headline)
                        .foregroundColor(plantDarkGreen) // Themed color
                        .padding(.top)
                        .padding(.horizontal) // Add horizontal padding for consistency
                    
                    List { // Removed `selection:` to restore custom tap behavior
                        ForEach(tasksToReview) { task in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(task.title)
                                        .font(.headline)
                                        // Strikethrough if main task is done AND no subtasks are pending
                                        .strikethrough(task.isDone && !task.subtasks.contains(where: {!$0.isDone}), color: plantDustyBlue) // Themed strikethrough
                                        .foregroundColor(task.isDone && !task.subtasks.contains(where: {!$0.isDone}) ? plantDustyBlue : plantDarkGreen) // Themed color
                                    
                                    if !task.detail.isEmpty {
                                        Text(task.detail)
                                            .font(.caption)
                                            .foregroundColor(plantMediumGreen) // Themed color
                                            .lineLimit(1)
                                    }
                                    Text("Original due: \(task.dueDate, style: .date)")
                                        .font(.caption2)
                                        .foregroundColor(plantPink) // Themed color for due date
                                    
                                    let pendingSubtasks = task.subtasks.filter { !$0.isDone }.count
                                    if pendingSubtasks > 0 {
                                        Text("\(pendingSubtasks) subtask(s) pending")
                                            .font(.caption2)
                                            .foregroundColor(plantDustyBlue) // Themed color
                                    } else if !task.subtasks.isEmpty && task.isDone {
                                        Text("All subtasks complete")
                                            .font(.caption2)
                                            .foregroundColor(plantMediumGreen) // Themed color
                                    }
                                }
                                Spacer()
                                // --- Reverted to custom checkbox Image and logic ---
                                Image(systemName: selectedTasksToMigrate.contains(task.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedTasksToMigrate.contains(task.id) ? plantDarkGreen : plantDustyBlue) // Themed colors
                                    .font(.title2)
                                // --- End custom checkbox ---
                            }
                            .contentShape(Rectangle()) // Make the whole row tappable
                            .onTapGesture { // Restore custom tap gesture
                                if selectedTasksToMigrate.contains(task.id) {
                                    selectedTasksToMigrate.remove(task.id)
                                } else {
                                    selectedTasksToMigrate.insert(task.id)
                                }
                            }
                            .listRowBackground(selectedTasksToMigrate.contains(task.id) ? plantPastelGreen.opacity(0.6) : plantBeige) // Themed selected/unselected background
                        }
                    }
                    .listStyle(.plain) // Use plain style for a flat, clean look
                    .background(plantBeige) // Ensure list background is themed
                }

                VStack(spacing: 15) {
                    if !tasksToReview.isEmpty {
                        Button {
                            processTaskSelections()
                            dismiss()
                        } label: {
                            Text("Confirm Selections (\(selectedTasksToMigrate.count) for Today)")
                                .font(.headline)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(selectedTasksToMigrate.isEmpty ? plantDustyBlue.opacity(0.5) : plantMediumGreen) // Themed dynamic background
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .disabled(selectedTasksToMigrate.isEmpty) // Disable if nothing is selected for migration
                        
                        Button {
                            if !tasksToReview.isEmpty {
                                deleteAllReviewedTasks()
                            }
                            dismiss()
                        } label: {
                            Text(tasksToReview.isEmpty ? "All Clear!" : "Discard All Reviewed Tasks")
                                .font(.headline)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(tasksToReview.isEmpty ? plantMediumGreen : plantPink.opacity(0.8)) // Themed dynamic background (green if clear, pink for discard)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                }
                .padding() // Padding around the buttons VStack
            }
            .background(plantBeige.edgesIgnoringSafeArea(.all)) // Overall view background
            .navigationTitle("") // Hide default title
            .navigationBarTitleDisplayMode(.inline) // Ensure custom title displays correctly
            .toolbarBackground(plantLightMintGreen, for: .navigationBar) // Themed navigation bar background
            .toolbarBackground(.visible, for: .navigationBar) // Make background visible
            .toolbar {
                ToolbarItem(placement: .principal) { // Custom title
                    Text("Review Old Tasks")
                        .fontWeight(.bold)
                        .foregroundColor(plantDarkGreen) // Themed title color
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { // "Later" button does not delete anything
                        dismiss()
                    }
                    .foregroundColor(plantDarkGreen) // Themed color
                }
            }
        }
        .navigationViewStyle(.stack) // Consistent navigation style
    }

    private func processTaskSelections() {
        let today = Calendar.current.startOfDay(for: Date())

        for taskInReview in tasksToReview {
            if selectedTasksToMigrate.contains(taskInReview.id) {
                taskInReview.dueDate = today
                taskInReview.isDone = false
                taskInReview.completedAt = nil
                print("Migrating task: \(taskInReview.title) to today. Subtask statuses preserved.")
            } else {
                print("Deleting unselected task: \(taskInReview.title)")
                modelContext.delete(taskInReview)
            }
        }
        
        do {
            try modelContext.save()
        } catch {
            print("Error saving context after processing task selections: \(error.localizedDescription)")
        }
    }

    private func deleteAllReviewedTasks() {
        for task in tasksToReview {
            print("Deleting task via 'Discard All': \(task.title)")
            modelContext.delete(task)
        }
        do {
            try modelContext.save()
        } catch {
            print("Error saving context after discarding all reviewed tasks: \(error.localizedDescription)")
        }
    }
}

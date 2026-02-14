import SwiftUI
import SwiftData
import FirebaseAuth

struct MigrateTasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var firebaseManager: FirebaseManager

    @Query private var allTodoItems: [TodoItem]
    @State private var selectedTasksToMigrate: Set<PersistentIdentifier> = []

    private var tasksToReview: [TodoItem] {
        allTodoItems.filter { todoItem in
            let isMainTaskIncomplete = !todoItem.isDone
            let hasIncompleteSubtasks = todoItem.subtasks.contains(where: { !$0.isDone })
            return isMainTaskIncomplete || hasIncompleteSubtasks
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if tasksToReview.isEmpty {
                Spacer()
                Text("No tasks need review or migration!")
                    .font(.title2)
                    .foregroundColor(dynamicSecondaryTextColor)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            } else {
                Text("Select tasks to move to today's list:")
                    .font(.headline)
                    .foregroundColor(dynamicTextColor)
                    .padding(.top)
                    .padding(.horizontal)
                
                List {
                    ForEach(tasksToReview) { task in
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(task.title)
                                    .font(.headline)
                                    .strikethrough(task.isDone && !task.subtasks.contains(where: {!$0.isDone}), color: dynamicSecondaryTextColor)
                                    .foregroundColor(task.isDone && !task.subtasks.contains(where: {!$0.isDone}) ? dynamicSecondaryTextColor : dynamicTextColor)
                                
                                if !task.detail.isEmpty {
                                    Text(task.detail)
                                        .font(.caption)
                                        .foregroundColor(dynamicSecondaryTextColor)
                                        .lineLimit(1)
                                }
                                
                                HStack(spacing: 8) {
                                    Text("Original due: \(task.dueDate, style: .date)")
                                        .font(.caption2)
                                        .foregroundColor(dynamicAccentColor)
                                    
                                    Text(task.origin == .today ? "Today" : "Master List")
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundColor(task.origin == .today ? dynamicPrimaryColor : dynamicAccentColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            task.origin == .today ? 
                                                dynamicPrimaryColor.opacity(0.15) : 
                                                dynamicAccentColor.opacity(0.15)
                                        )
                                        .cornerRadius(4)
                                }
                                
                                let pendingSubtasks = task.subtasks.filter { !$0.isDone }.count
                                if pendingSubtasks > 0 {
                                    Text("\(pendingSubtasks) subtask(s) pending")
                                        .font(.caption2)
                                        .foregroundColor(dynamicSecondaryTextColor)
                                } else if !task.subtasks.isEmpty && task.isDone {
                                    Text("All subtasks complete")
                                        .font(.caption2)
                                        .foregroundColor(dynamicSecondaryColor)
                                }
                            }
                            Spacer()
                            Image(systemName: selectedTasksToMigrate.contains(task.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedTasksToMigrate.contains(task.id) ? dynamicPrimaryColor : dynamicSecondaryTextColor)
                                .font(.title2)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedTasksToMigrate.contains(task.id) {
                                selectedTasksToMigrate.remove(task.id)
                            } else {
                                selectedTasksToMigrate.insert(task.id)
                            }
                        }
                        .listRowBackground(selectedTasksToMigrate.contains(task.id) ? dynamicPrimaryColor.opacity(0.3) : dynamicSecondaryBackgroundColor)
                    }
                }
                .listStyle(.plain)
                .background(dynamicBackgroundColor)
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
                            .background(selectedTasksToMigrate.isEmpty ? dynamicSecondaryTextColor.opacity(0.5) : dynamicPrimaryColor)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    
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
                            .background(tasksToReview.isEmpty ? dynamicSecondaryColor : dynamicDestructiveColor.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
            }
            .padding()
        }
        .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Review Old Tasks")
                    .fontWeight(.bold)
                    .foregroundColor(dynamicTextColor)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Later") {
                    dismiss()
                }
                .foregroundColor(dynamicPrimaryColor)
            }
        }
    }

    private func processTaskSelections() {
        let today = Calendar.current.startOfDay(for: Date())

        for taskInReview in tasksToReview {
            if selectedTasksToMigrate.contains(taskInReview.id) {
                taskInReview.dueDate = today
                taskInReview.origin = .today
                taskInReview.isDone = false
                taskInReview.completedAt = nil
                print("Migrating task: \(taskInReview.title) to today. Subtask statuses preserved.")
                
                // Sync migration to Firebase if shared
                if taskInReview.sharedTaskId != nil {
                    firebaseManager.syncLocalTaskToSharedTask(localTask: taskInReview) { error in
                        if let error = error {
                            print("Failed to sync migrated task: \(error)")
                        }
                    }
                }
            } else if taskInReview.origin == .today {
                    print("Deleting unselected TODAY task: \(taskInReview.title)")
                    
                    // Mark as discarded in Firebase if shared
                    if let sharedId = taskInReview.sharedTaskId {
                        firebaseManager.markSharedTaskDiscarded(sharedTaskId: sharedId) { error in
                            if let error = error {
                                print("Failed to mark shared task as discarded: \(error.localizedDescription)")
                            } else {
                                print("✅ Marked shared task as discarded in Firebase")
                            }
                        }
                    }
                    
                    let taskId = taskInReview.localTaskId
                    modelContext.delete(taskInReview)
                    
                    // Sync deletion to Firebase
                    FirebaseManager.shared.deleteTodoItem(localTaskId: taskId) { error in
                        if let error = error {
                            print("MigrateTasksView: Failed to delete task from Firebase: \(error.localizedDescription)")
                        } else {
                            print("MigrateTasksView: Successfully deleted task from Firebase")
                        }
                    }
                } else {
                    print("Keeping unselected MASTER task: \(taskInReview.title)")
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
            
            // Mark as discarded in Firebase if shared
            if let sharedId = task.sharedTaskId {
                firebaseManager.markSharedTaskDiscarded(sharedTaskId: sharedId) { error in
                    if let error = error {
                        print("Failed to mark shared task '\(task.title)' as discarded: \(error.localizedDescription)")
                    } else {
                        print("✅ Marked shared task '\(task.title)' as discarded in Firebase")
                    }
                }
            }
            
            let taskId = task.localTaskId
            modelContext.delete(task)
            
            // Sync deletion to Firebase
            FirebaseManager.shared.deleteTodoItem(localTaskId: taskId) { error in
                if let error = error {
                    print("MigrateTasksView: Failed to delete task '\(task.title)' from Firebase: \(error.localizedDescription)")
                } else {
                    print("MigrateTasksView: Successfully deleted task '\(task.title)' from Firebase")
                }
            }
        }
        do {
            try modelContext.save()
        } catch {
            print("Error saving context after discarding all reviewed tasks: \(error.localizedDescription)")
        }
    }
}

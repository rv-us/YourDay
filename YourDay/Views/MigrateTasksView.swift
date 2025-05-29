import SwiftUI
import SwiftData

struct MigrateTasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allTodoItems: [TodoItem]
    // Changed to store PersistentIdentifier for direct comparison with task.id
    @State private var selectedTasksToMigrate: Set<PersistentIdentifier> = []

    private var tasksToReview: [TodoItem] {
        allTodoItems.filter { todoItem in
            let isMainTaskIncomplete = !todoItem.isDone
            let hasIncompleteSubtasks = todoItem.subtasks.contains(where: { !$0.isDone })
            return isMainTaskIncomplete || hasIncompleteSubtasks
        }
    }

    var body: some View {
        NavigationView {
            VStack {
                if tasksToReview.isEmpty {
                    Spacer()
                    Text("No relevant tasks to review or migrate!")
                        .font(.title2)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                } else {
                    Text("Select tasks with incomplete items to move to today's list:")
                        .font(.headline)
                        .padding(.top)
                    
                    List {
                        ForEach(tasksToReview) { task in // task.id here is PersistentIdentifier
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(task.title)
                                        .font(.headline)
                                        // Strikethrough if main task is done AND no subtasks are pending
                                        .strikethrough(task.isDone && !task.subtasks.contains(where: {!$0.isDone}), color: .gray)
                                    
                                    // Corrected: If task.detail is String (not String?)
                                    if !task.detail.isEmpty { // Assuming task.detail is non-optional String
                                        Text(task.detail)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                            .lineLimit(1)
                                    }
                                    Text("Original due: \(task.dueDate, style: .date)")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                    
                                    let pendingSubtasks = task.subtasks.filter { !$0.isDone }.count
                                    if pendingSubtasks > 0 {
                                        Text("\(pendingSubtasks) subtask(s) pending")
                                            .font(.caption2)
                                            .foregroundColor(.purple)
                                    } else if !task.subtasks.isEmpty && task.isDone {
                                        Text("All subtasks complete")
                                            .font(.caption2)
                                            .foregroundColor(.green)
                                    }
                                }
                                Spacer()
                                // Use task.id (PersistentIdentifier) for selection state
                                Image(systemName: selectedTasksToMigrate.contains(task.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedTasksToMigrate.contains(task.id) ? .blue : .gray)
                                    .font(.title2)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Use task.id (PersistentIdentifier) for selection
                                if selectedTasksToMigrate.contains(task.id) {
                                    selectedTasksToMigrate.remove(task.id)
                                } else {
                                    selectedTasksToMigrate.insert(task.id)
                                }
                            }
                        }
                    }
                }

                VStack(spacing: 15) {
                    if !tasksToReview.isEmpty {
                        Button {
                            migrateSelectedTasks()
                            dismiss()
                        } label: {
                            Text("Add \(selectedTasksToMigrate.count) Selected to Today")
                                .font(.headline)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(selectedTasksToMigrate.isEmpty ? Color.gray.opacity(0.5) : Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .disabled(selectedTasksToMigrate.isEmpty)
                    }

                    Button {
                        if !tasksToReview.isEmpty {
                             clearAllReviewedTasks()
                        }
                        dismiss()
                    } label: {
                        Text(tasksToReview.isEmpty ? "All Clear! Start Fresh" : "Skip & Delete Reviewed Tasks")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(tasksToReview.isEmpty ? Color.green : Color.red.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding()
            }
            .navigationTitle("Review Incomplete Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func migrateSelectedTasks() {
        let today = Calendar.current.startOfDay(for: Date())
        // taskID is now a PersistentIdentifier
        for taskID in selectedTasksToMigrate {
            // Find the original task by its PersistentIdentifier
            if let originalTask = tasksToReview.first(where: { $0.id == taskID }) {
                
                let newSubtasks = originalTask.subtasks.map { oldSubtask in
                    Subtask(id: UUID(), title: oldSubtask.title, isDone: false, completedAt: nil)
                }

                let newTask = TodoItem(
                    title: originalTask.title,
                    detail: originalTask.detail,
                    dueDate: today,
                    isDone: false,
                    subtasks: newSubtasks
                )
                
                modelContext.insert(newTask)
                modelContext.delete(originalTask)
            }
        }
        
        do {
            try modelContext.save()
        } catch {
            print("Error saving context after migrating tasks: \(error.localizedDescription)")
        }
    }

    private func clearAllReviewedTasks() {
        for task in tasksToReview {
            modelContext.delete(task)
        }
        do {
            try modelContext.save()
        } catch {
            print("Error saving context after clearing reviewed tasks: \(error.localizedDescription)")
        }
    }
}

import SwiftUI
import SwiftData

struct MigrateTasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

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
                            VStack(alignment: .leading) {
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
                                Text("Original due: \(task.dueDate, style: .date)")
                                    .font(.caption2)
                                    .foregroundColor(dynamicAccentColor)
                                
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

import SwiftUI
import SwiftData
import FirebaseAuth

struct MigrateTasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var firebaseManager: FirebaseManager

    /// Called after the user confirms the review, with the number of tasks placed on today.
    /// Lets the daily dashboard check off the Migrate step only when a real migration happened.
    var onMigrationConfirmed: ((Int) -> Void)? = nil

    @Query private var allTodoItems: [TodoItem]
    @State private var selectedTasksToMigrate: Set<PersistentIdentifier> = []
    @State private var isProcessingSelections = false
    @State private var migrationCalendarError: String?

    private var tasksToReview: [TodoItem] {
        allTodoItems
            .filter { todoItem in
                let isMainTaskIncomplete = !todoItem.isDone
                let hasIncompleteSubtasks = todoItem.subtasks.contains(where: { !$0.isDone })
                return isMainTaskIncomplete || hasIncompleteSubtasks
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func daysOld(_ task: TodoItem) -> Int {
        let seconds = Date().timeIntervalSince(task.createdAt)
        return max(0, Int(seconds / 86_400))
    }

    private func ageLabel(_ task: TodoItem) -> String {
        switch daysOld(task) {
        case 0: return "Created today"
        case 1: return "Created yesterday"
        case let n: return "Created \(n) days ago"
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("Select tasks to move to today's list:")
                        .font(.headline)
                        .foregroundColor(dynamicTextColor)
                    Text("Unselected Today tasks will return to Master List.")
                        .font(.subheadline)
                        .foregroundColor(dynamicSecondaryTextColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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

                                Text(ageLabel(task))
                                    .font(.caption2)
                                    .fontWeight(daysOld(task) >= 7 ? .semibold : .regular)
                                    .foregroundColor(daysOld(task) >= 7 ? .orange : dynamicSecondaryTextColor)
                                
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteTask(task)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .background(dynamicBackgroundColor)
            }

            VStack(spacing: 15) {
                if !tasksToReview.isEmpty {
                    Button {
                        processTaskSelections {
                            dismiss()
                        }
                    } label: {
                        Text(isProcessingSelections
                            ? "Updating calendar…"
                            : "Confirm Selections (\(selectedTasksToMigrate.count) for Today)")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(selectedTasksToMigrate.isEmpty ? dynamicSecondaryTextColor.opacity(0.5) : dynamicPrimaryColor)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .disabled(isProcessingSelections)
                    
                    Button {
                        if !tasksToReview.isEmpty {
                            deleteAllReviewedTasks()
                        }
                        dismiss()
                    } label: {
                        Text(tasksToReview.isEmpty ? "All Clear!" : "Delete All Reviewed Tasks")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(tasksToReview.isEmpty ? dynamicSecondaryColor : dynamicDestructiveColor.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }

                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .foregroundColor(dynamicPrimaryColor)
                        .background(dynamicSecondaryBackgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(dynamicPrimaryColor.opacity(0.5), lineWidth: 1.5)
                        )
                        .cornerRadius(10)
                }
                .disabled(isProcessingSelections)
            }
            .padding()
        }
        .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
        .alert("Could Not Update Calendar", isPresented: Binding(
            get: { migrationCalendarError != nil },
            set: { if !$0 { migrationCalendarError = nil } }
        )) {
            Button("OK", role: .cancel) {
                migrationCalendarError = nil
            }
        } message: {
            Text(migrationCalendarError ?? "Something went wrong removing scheduled tasks from your calendar.")
        }
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
        }
    }

    private func defaultFutureDueDate() -> Date {
        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .day, value: 1, to: today) ?? Date()
    }

    private func finishMoveToMasterList(_ task: TodoItem) {
        task.origin = .master
        task.dueDate = defaultFutureDueDate()
        print("Moving unselected TODAY task to Master List: \(task.title)")

        if task.trelloCardId != nil {
            Task { await TrelloTaskSyncService.pushEdit(for: task) }
        }

        if task.sharedTaskId != nil {
            firebaseManager.syncLocalTaskToSharedTask(localTask: task) { error in
                if let error = error {
                    print("MigrateTasksView: Failed to sync moved task to shared task: \(error.localizedDescription)")
                }
            }
        }

        if let userId = Auth.auth().currentUser?.uid {
            let codableTask = TodoItemCodable(from: task, userId: userId)
            firebaseManager.saveTodoItem(codableTask) { error in
                if let error = error {
                    print("MigrateTasksView: Failed to sync task move to Firebase: \(error.localizedDescription)")
                } else {
                    print("MigrateTasksView: Successfully synced task move to Firebase")
                }
            }
        }
    }

    private func processTaskSelections(onComplete: @escaping () -> Void = {}) {
        let today = Calendar.current.startOfDay(for: Date())
        let tasksMovingToMaster = tasksToReview.filter {
            !selectedTasksToMigrate.contains($0.id) && $0.origin == .today
        }

        isProcessingSelections = true

        func applyTodaySelections() {
            var migratedToTodayCount = 0
            for taskInReview in tasksToReview {
                if selectedTasksToMigrate.contains(taskInReview.id) {
                    taskInReview.dueDate = today
                    taskInReview.origin = .today
                    taskInReview.isDone = false
                    taskInReview.completedAt = nil
                    migratedToTodayCount += 1
                    print("Migrating task: \(taskInReview.title) to today. Subtask statuses preserved.")

                    if taskInReview.sharedTaskId != nil {
                        firebaseManager.syncLocalTaskToSharedTask(localTask: taskInReview) { error in
                            if let error = error {
                                print("Failed to sync migrated task: \(error)")
                            }
                        }
                    }
                } else if taskInReview.origin != .today {
                    print("Keeping unselected MASTER task: \(taskInReview.title)")
                }
            }

            do {
                try modelContext.save()
            } catch {
                print("Error saving context after processing task selections: \(error.localizedDescription)")
            }
            isProcessingSelections = false
            onMigrationConfirmed?(migratedToTodayCount)
            onComplete()
        }

        guard !tasksMovingToMaster.isEmpty else {
            applyTodaySelections()
            return
        }

        var remaining = tasksMovingToMaster
        func detachNext() {
            guard let task = remaining.first else {
                applyTodaySelections()
                return
            }
            remaining.removeFirst()

            let hasCalendarLink = !(task.manualScheduleGoogleEventId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
            guard hasCalendarLink else {
                finishMoveToMasterList(task)
                detachNext()
                return
            }

            ManualCalendarEventDeletionService.detachTaskFromManualScheduleWhenMovingToMaster(
                task,
                modelContext: modelContext,
                firebaseManager: firebaseManager
            ) { error in
                DispatchQueue.main.async {
                    if let error {
                        migrationCalendarError = error.localizedDescription
                        isProcessingSelections = false
                        return
                    }
                    finishMoveToMasterList(task)
                    detachNext()
                }
            }
        }
        detachNext()
    }

    private func deleteTask(_ item: TodoItem) {
        selectedTasksToMigrate.remove(item.id)

        if item.trelloCardId != nil {
            Task { @MainActor in
                await TrelloTaskSyncService.deleteRemoteCardIfNeeded(for: item)
                deleteLocalTask(item)
                saveAfterDelete()
            }
            return
        }
        deleteLocalTask(item)
        saveAfterDelete()
    }

    private func deleteLocalTask(_ item: TodoItem) {
        let taskId = item.localTaskId

        if let sharedId = item.sharedTaskId {
            if item.isDone {
                firebaseManager.deleteSharedTask(sharedTaskId: sharedId) { error in
                    if let error = error { print("Failed to delete shared task: \(error)") }
                }
            } else {
                firebaseManager.markSharedTaskDiscarded(sharedTaskId: sharedId) { error in
                    if let error = error { print("Failed to mark shared task as discarded: \(error)") }
                }
            }
        }

        modelContext.delete(item)

        firebaseManager.deleteTodoItem(localTaskId: taskId) { error in
            if let error = error {
                print("MigrateTasksView: Failed to delete task from Firebase: \(error.localizedDescription)")
            } else {
                print("MigrateTasksView: Successfully deleted task from Firebase")
            }
        }
    }

    private func saveAfterDelete() {
        do {
            try modelContext.save()
        } catch {
            print("Error saving context after deleting task: \(error.localizedDescription)")
        }
    }

    private func deleteAllReviewedTasks() {
        let tasks = tasksToReview
        selectedTasksToMigrate.removeAll()
        for task in tasks {
            print("Deleting task via 'Delete All': \(task.title)")
            if task.trelloCardId != nil {
                Task { @MainActor in
                    await TrelloTaskSyncService.deleteRemoteCardIfNeeded(for: task)
                    deleteLocalTask(task)
                    saveAfterDelete()
                }
            } else {
                deleteLocalTask(task)
            }
        }
        saveAfterDelete()
    }
}

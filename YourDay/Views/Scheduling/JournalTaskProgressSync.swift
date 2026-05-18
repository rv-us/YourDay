import Foundation
import SwiftData
import FirebaseAuth

@MainActor
enum JournalTaskProgressSync {
    struct SubtaskSelectionKey: Hashable {
        let taskId: String
        let subtaskId: UUID
    }

    static func scheduledTaskTitles(for event: TaskEndMonitor.PendingJournalEvent) -> [String] {
        var titles = event.tasks.isEmpty ? [event.taskTitle] : event.tasks
        let normalizedEventTitle = normalizedTitle(event.taskTitle)
        if !titles.map(normalizedTitle).contains(normalizedEventTitle) {
            titles.append(event.taskTitle)
        }
        return titles
    }

    static func matchedTaskIndices(in todoItems: [TodoItem], for event: TaskEndMonitor.PendingJournalEvent) -> [Int] {
        let normalizedScheduledTitles = Set(scheduledTaskTitles(for: event).map(normalizedTitle))
        return todoItems.indices.filter { index in
            normalizedScheduledTitles.contains(normalizedTitle(todoItems[index].title))
        }
    }

    static func normalizedTitle(_ rawTitle: String) -> String {
        let collapsedWhitespace = rawTitle
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsedWhitespace.lowercased()
    }

    static func markAllMatchedCompleted(
        in todoItems: [TodoItem],
        for event: TaskEndMonitor.PendingJournalEvent,
        completionTime: Date,
        modelContext: ModelContext,
        firebaseManager: FirebaseManager = .shared,
        logPrefix: String
    ) {
        let matchedTasks = matchedTaskIndices(in: todoItems, for: event).map { todoItems[$0] }
        guard !matchedTasks.isEmpty else { return }

        for task in matchedTasks {
            markTaskCompleted(task, completionTime: completionTime)
        }

        saveAndSync(
            matchedTasks,
            modelContext: modelContext,
            firebaseManager: firebaseManager,
            logPrefix: logPrefix
        )
    }

    static func applyPartialSubtaskSelection(
        in todoItems: [TodoItem],
        for event: TaskEndMonitor.PendingJournalEvent,
        selectedSubtaskKeys: Set<SubtaskSelectionKey>,
        completionTime: Date,
        modelContext: ModelContext,
        firebaseManager: FirebaseManager = .shared,
        logPrefix: String
    ) {
        let matchedTasks = matchedTaskIndices(in: todoItems, for: event).map { todoItems[$0] }
        guard !matchedTasks.isEmpty else { return }

        var changedTasks: [TodoItem] = []
        for task in matchedTasks {
            guard !task.subtasks.isEmpty else { continue }

            for subtaskIndex in task.subtasks.indices {
                let subtaskId = task.subtasks[subtaskIndex].id
                let key = SubtaskSelectionKey(taskId: task.localTaskId, subtaskId: subtaskId)
                let shouldBeDone = selectedSubtaskKeys.contains(key)

                task.subtasks[subtaskIndex].isDone = shouldBeDone
                task.subtasks[subtaskIndex].completedAt = shouldBeDone ? completionTime : nil
            }

            let taskCompleted = task.subtasks.allSatisfy(\.isDone)
            task.isDone = taskCompleted
            task.completedAt = taskCompleted ? completionTime : nil
            changedTasks.append(task)
        }

        saveAndSync(
            changedTasks,
            modelContext: modelContext,
            firebaseManager: firebaseManager,
            logPrefix: logPrefix
        )
    }

    static func applyPartialCompletion(
        in todoItems: [TodoItem],
        for event: TaskEndMonitor.PendingJournalEvent,
        completedTitles: [String],
        completionTime: Date,
        modelContext: ModelContext,
        firebaseManager: FirebaseManager = .shared,
        logPrefix: String
    ) {
        let normalizedCompletedTitles = Set(completedTitles.map(normalizedTitle))
        guard !normalizedCompletedTitles.isEmpty else { return }

        let matchedTasks = matchedTaskIndices(in: todoItems, for: event)
            .map { todoItems[$0] }
            .filter { normalizedCompletedTitles.contains(normalizedTitle($0.title)) }
        guard !matchedTasks.isEmpty else { return }

        for task in matchedTasks {
            markTaskCompleted(task, completionTime: completionTime)
        }

        saveAndSync(
            matchedTasks,
            modelContext: modelContext,
            firebaseManager: firebaseManager,
            logPrefix: logPrefix
        )
    }

    private static func markTaskCompleted(_ task: TodoItem, completionTime: Date) {
        task.isDone = true
        task.completedAt = completionTime

        for subtaskIndex in task.subtasks.indices {
            task.subtasks[subtaskIndex].isDone = true
            task.subtasks[subtaskIndex].completedAt = completionTime
        }
    }

    private static func saveAndSync(
        _ tasks: [TodoItem],
        modelContext: ModelContext,
        firebaseManager: FirebaseManager,
        logPrefix: String
    ) {
        guard !tasks.isEmpty else { return }

        do {
            try modelContext.save()
        } catch {
            print("\(logPrefix): Failed to save task updates from journal check-in: \(error.localizedDescription)")
        }

        tasks.forEach { syncTaskToFirebase($0, firebaseManager: firebaseManager, logPrefix: logPrefix) }
        NotificationManager.shared.rescheduleIfNeeded(context: modelContext)
    }

    private static func syncTaskToFirebase(_ task: TodoItem, firebaseManager: FirebaseManager, logPrefix: String) {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let codableTask = TodoItemCodable(from: task, userId: userId)
        firebaseManager.saveTodoItem(codableTask) { error in
            if let error = error {
                print("\(logPrefix): Failed to sync task '\(task.title)' to Firebase: \(error.localizedDescription)")
            }
        }

        if task.sharedTaskId != nil {
            firebaseManager.syncLocalTaskToSharedTask(localTask: task) { error in
                if let error = error {
                    print("\(logPrefix): Failed to sync shared task '\(task.title)': \(error.localizedDescription)")
                }
            }
        }
    }
}

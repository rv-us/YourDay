import Foundation
import SwiftData
import FirebaseAuth
import FirebaseFirestore

enum ScheduledSessionCompletionCoordinator {
    private static let minimumCalendarEventDuration: TimeInterval = 60

    /// `true` when a task is linked to a manual calendar block and completed before that block’s end.
    /// Proof capture is skipped in this case; the journal flow runs next.
    static func isCompletingScheduledBlockEarly(_ task: TodoItem) -> Bool {
        let eventId = task.manualScheduleGoogleEventId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !eventId.isEmpty, task.isDone, let end = task.scheduledEndTime else { return false }
        let completion = task.completedAt ?? Date()
        return completion < end
    }

    static func handleEarlyCompletion(
        for completedTask: TodoItem,
        modelContext: ModelContext,
        firebaseManager: FirebaseManager = .shared,
        journalViewModel: JournalViewModel = .shared
    ) {
        let eventId = completedTask.manualScheduleGoogleEventId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !eventId.isEmpty else { return }
        guard completedTask.isDone else { return }
        guard let originalStart = completedTask.scheduledStartTime,
              let originalEnd = completedTask.scheduledEndTime else { return }

        let completionTime = completedTask.completedAt ?? Date()
        guard completionTime < originalEnd else { return }

        let descriptor = FetchDescriptor<TodoItem>(sortBy: [SortDescriptor(\.position)])
        let allTasks = (try? modelContext.fetch(descriptor)) ?? []
        let linkedTasks = allTasks.filter {
            ($0.manualScheduleGoogleEventId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") == eventId
        }
        guard !linkedTasks.isEmpty else { return }

        let boundedCompletionTime = boundedEndTime(
            completionTime,
            start: originalStart,
            end: originalEnd
        )

        let remainingTasks = linkedTasks.filter { !$0.isDone }
        let completedSegmentTasks = linkedTasks.filter { $0.isDone }
        let completedTitles = uniqueTitles(from: completedSegmentTasks.map(\.title))
        let remainingTitles = uniqueTitles(from: remainingTasks.map(\.title))

        firebaseManager.fetchScheduledEvent(eventId: eventId) { eventData, _ in
            let currentTitle = (eventData?["taskTitle"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTitle(from: linkedTasks)
            let oldTasks = (eventData?["tasks"] as? [String]) ?? uniqueTitles(from: linkedTasks.map(\.title))
            let sessionStart = dateValue(from: eventData?["startTime"]) ?? originalStart
            let sessionEnd = dateValue(from: eventData?["endTime"]) ?? originalEnd

            let baseTitle = currentTitle.isEmpty ? fallbackTitle(from: linkedTasks) : currentTitle
            let updatedCurrentTitle = completedTitles.isEmpty ? baseTitle : buildSessionTitle(for: completedTitles)
            let oldDescription = descriptionBody(for: oldTasks)

            let calendarManager = GoogleCalendarManager.shared
            calendarManager.ensureCalendarWriteAccess { accessResult in
                DispatchQueue.main.async {
                    switch accessResult {
                    case .failure(let error):
                        print("ScheduledSessionCompletionCoordinator: calendar access failed: \(error.localizedDescription)")
                    case .success:
                        calendarManager.updateCalendarEvent(
                            eventId: eventId,
                            title: updatedCurrentTitle,
                            start: sessionStart,
                            end: boundedCompletionTime,
                            description: oldDescription
                        ) { _, error in
                            DispatchQueue.main.async {
                                if let error {
                                    print("ScheduledSessionCompletionCoordinator: failed to truncate event: \(error.localizedDescription)")
                                    return
                                }

                                let remainingIds = Set(remainingTasks.map(\.localTaskId))
                                linkedTasks.forEach { task in
                                    if remainingIds.contains(task.localTaskId) {
                                        task.scheduledStartTime = boundedCompletionTime
                                        task.scheduledEndTime = sessionEnd
                                    } else {
                                        task.scheduledStartTime = sessionStart
                                        task.scheduledEndTime = boundedCompletionTime
                                    }
                                }

                                firebaseManager.updateScheduledEvent(
                                    eventId: eventId,
                                    taskTitle: updatedCurrentTitle,
                                    tasks: completedTitles.isEmpty ? oldTasks : completedTitles,
                                    startTime: sessionStart,
                                    endTime: boundedCompletionTime,
                                    promptSkipped: false
                                ) { err in
                                    if let err {
                                        print("ScheduledSessionCompletionCoordinator: failed to update truncated scheduled event: \(err.localizedDescription)")
                                    }
                                }

                                NotificationManager.shared.cancelJournalPromptNotification(eventId: eventId)

                                if remainingTasks.isEmpty {
                                    saveTasksAndSync(
                                        tasks: linkedTasks,
                                        modelContext: modelContext,
                                        firebaseManager: firebaseManager
                                    )
                                    ScreenTimeManager.shared.scheduleSnapshotRefresh(context: modelContext)
                                    journalViewModel.enqueueImmediateScheduledJournalPrompt(
                                        eventId: eventId,
                                        taskTitle: updatedCurrentTitle,
                                        tasks: completedTitles.isEmpty ? oldTasks : completedTitles,
                                        scheduledStartTime: sessionStart,
                                        scheduledEndTime: boundedCompletionTime
                                    )
                                    return
                                }

                                let newTitle = buildSessionTitle(for: remainingTitles)
                                let newDescription = descriptionBody(for: remainingTitles)

                                calendarManager.createCalendarEvent(
                                    title: newTitle,
                                    start: boundedCompletionTime,
                                    end: sessionEnd,
                                    description: newDescription
                                ) { newEventId, createError in
                                    DispatchQueue.main.async {
                                        if let createError {
                                            print("ScheduledSessionCompletionCoordinator: failed to create split event: \(createError.localizedDescription)")
                                            saveTasksAndSync(
                                                tasks: linkedTasks,
                                                modelContext: modelContext,
                                                firebaseManager: firebaseManager
                                            )
                                            ScreenTimeManager.shared.scheduleSnapshotRefresh(context: modelContext)
                                            journalViewModel.enqueueImmediateScheduledJournalPrompt(
                                                eventId: eventId,
                                                taskTitle: updatedCurrentTitle,
                                                tasks: completedTitles.isEmpty ? oldTasks : completedTitles,
                                                scheduledStartTime: sessionStart,
                                                scheduledEndTime: boundedCompletionTime
                                            )
                                            return
                                        }

                                        guard let newEventId, !newEventId.isEmpty else {
                                            saveTasksAndSync(
                                                tasks: linkedTasks,
                                                modelContext: modelContext,
                                                firebaseManager: firebaseManager
                                            )
                                            ScreenTimeManager.shared.scheduleSnapshotRefresh(context: modelContext)
                                            journalViewModel.enqueueImmediateScheduledJournalPrompt(
                                                eventId: eventId,
                                                taskTitle: updatedCurrentTitle,
                                                tasks: completedTitles.isEmpty ? oldTasks : completedTitles,
                                                scheduledStartTime: sessionStart,
                                                scheduledEndTime: boundedCompletionTime
                                            )
                                            return
                                        }

                                        for task in remainingTasks {
                                            task.manualScheduleGoogleEventId = newEventId
                                            task.scheduledStartTime = boundedCompletionTime
                                            task.scheduledEndTime = sessionEnd
                                        }

                                        firebaseManager.saveScheduledEvent(
                                            eventId: newEventId,
                                            taskTitle: newTitle,
                                            tasks: remainingTitles,
                                            startTime: boundedCompletionTime,
                                            endTime: sessionEnd
                                        ) { saveError in
                                            if let saveError {
                                                print("ScheduledSessionCompletionCoordinator: failed to save split event mapping: \(saveError.localizedDescription)")
                                            }
                                        }

                                        NotificationManager.shared.scheduleJournalPromptNotification(
                                            eventId: newEventId,
                                            taskTitle: newTitle,
                                            scheduledEndTime: sessionEnd
                                        )

                                        saveTasksAndSync(
                                            tasks: linkedTasks,
                                            modelContext: modelContext,
                                            firebaseManager: firebaseManager
                                        )
                                        ScreenTimeManager.shared.scheduleSnapshotRefresh(context: modelContext)

                                        journalViewModel.enqueueImmediateScheduledJournalPrompt(
                                            eventId: eventId,
                                            taskTitle: updatedCurrentTitle,
                                            tasks: completedTitles.isEmpty ? oldTasks : completedTitles,
                                            scheduledStartTime: sessionStart,
                                            scheduledEndTime: boundedCompletionTime
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private static func saveTasksAndSync(
        tasks: [TodoItem],
        modelContext: ModelContext,
        firebaseManager: FirebaseManager
    ) {
        do {
            try modelContext.save()
        } catch {
            print("ScheduledSessionCompletionCoordinator: failed saving local tasks: \(error.localizedDescription)")
        }

        guard let userId = Auth.auth().currentUser?.uid else { return }
        for task in tasks {
            let codable = TodoItemCodable(from: task, userId: userId)
            firebaseManager.saveTodoItem(codable) { error in
                if let error {
                    print("ScheduledSessionCompletionCoordinator: failed syncing task '\(task.title)': \(error.localizedDescription)")
                }
            }
        }
    }

    private static func boundedEndTime(_ completion: Date, start: Date, end: Date) -> Date {
        let minEnd = start.addingTimeInterval(minimumCalendarEventDuration)
        return min(max(completion, minEnd), end)
    }

    private static func uniqueTitles(from titles: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for title in titles {
            let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            let key = t.lowercased()
            if seen.insert(key).inserted {
                ordered.append(t)
            }
        }
        return ordered
    }

    private static func buildSessionTitle(for titles: [String]) -> String {
        if titles.isEmpty {
            return "Working Session"
        }
        if titles.count == 1 {
            return titles[0]
        }
        return "\(titles[0]) and \(titles.count - 1) more"
    }

    private static func fallbackTitle(from tasks: [TodoItem]) -> String {
        buildSessionTitle(for: uniqueTitles(from: tasks.map(\.title)))
    }

    private static func descriptionBody(for titles: [String]) -> String {
        let taskLines = titles.map { "• \($0)" }.joined(separator: "\n")
        let marker = "\n\n[YourDay Scheduled Task]"
        if taskLines.isEmpty {
            return "Tasks:\n• Working Session\(marker)"
        }
        return "Tasks:\n\(taskLines)\(marker)"
    }

    private static func dateValue(from raw: Any?) -> Date? {
        if let timestamp = raw as? Timestamp {
            return timestamp.dateValue()
        }
        if let date = raw as? Date {
            return date
        }
        return nil
    }

}

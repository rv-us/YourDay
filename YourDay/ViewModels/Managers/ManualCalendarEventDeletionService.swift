//
//  ManualCalendarEventDeletionService.swift
//  YourDay
//
//  Shared: delete Google Calendar event(s) for YourDay manual scheduling, unlink SwiftData
//  todos, clear journal notifications / Firestore `scheduledEvents`, and refresh screen-time snapshot.
//  Used by `ManualSchedulingView` and `ScheduledTaskPopupSheet` (Google calendar UI).
//

import Foundation
import SwiftData
import FirebaseAuth

enum ManualCalendarEventDeletionService {
    // MARK: - Move Today → Master

    /// Removes a task from manual scheduling when it leaves Today: deletes the Google event if it
    /// was the only linked task, otherwise updates the event for the remaining Today tasks.
    static func detachTaskFromManualScheduleWhenMovingToMaster(
        _ task: TodoItem,
        modelContext: ModelContext,
        firebaseManager: FirebaseManager,
        completion: @escaping (Error?) -> Void
    ) {
        let eventId = task.manualScheduleGoogleEventId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !eventId.isEmpty else {
            completion(nil)
            return
        }

        let descriptor = FetchDescriptor<TodoItem>(sortBy: [SortDescriptor(\.position)])
        let all: [TodoItem] = (try? modelContext.fetch(descriptor)) ?? []
        let linkedTasks = all.filter {
            ($0.manualScheduleGoogleEventId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") == eventId
        }
        let remainingLinked = linkedTasks.filter { $0.localTaskId != task.localTaskId }

        if remainingLinked.isEmpty {
            deleteGoogleCalendarEventsAndUnlinkLocalTasks(
                eventIds: [eventId],
                modelContext: modelContext,
                firebaseManager: firebaseManager,
                completion: completion
            )
            return
        }

        guard let start = remainingLinked.compactMap(\.scheduledStartTime).min(),
              let end = remainingLinked.compactMap(\.scheduledEndTime).max() else {
            clearLocalSchedule(for: task)
            try? modelContext.save()
            syncTaskToFirebase(task, firebaseManager: firebaseManager)
            refreshScreenTimeSnapshot(context: modelContext)
            completion(nil)
            return
        }

        let payload = googleCalendarPayload(for: remainingLinked)
        GoogleCalendarManager.shared.ensureCalendarWriteAccess { accessResult in
            DispatchQueue.main.async {
                switch accessResult {
                case .failure(let err):
                    completion(err)
                case .success:
                    GoogleCalendarManager.shared.updateCalendarEvent(
                        eventId: eventId,
                        title: payload.title,
                        start: start,
                        end: end,
                        description: payload.description
                    ) { _, err in
                        DispatchQueue.main.async {
                            if let err = err {
                                completion(err)
                                return
                            }
                            clearLocalSchedule(for: task)
                            try? modelContext.save()
                            syncTaskToFirebase(task, firebaseManager: firebaseManager)
                            refreshScreenTimeSnapshot(context: modelContext)
                            completion(nil)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Delete events

    /// Deletes the given event id(s) from Google Calendar, then unlinks every `TodoItem` whose
    /// `manualScheduleGoogleEventId` matches, syncs to Firebase, and updates screen-time snapshot.
    static func deleteGoogleCalendarEventsAndUnlinkLocalTasks(
        eventIds: [String],
        modelContext: ModelContext,
        firebaseManager: FirebaseManager,
        completion: @escaping (Error?) -> Void
    ) {
        let idSet = Set(
            eventIds
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        guard !idSet.isEmpty else {
            completion(nil)
            return
        }

        let descriptor = FetchDescriptor<TodoItem>(sortBy: [SortDescriptor(\.position)])
        let all: [TodoItem] = (try? modelContext.fetch(descriptor)) ?? []
        let tasksToUnlink: [TodoItem] = all.filter { task in
            let m = task.manualScheduleGoogleEventId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !m.isEmpty && idSet.contains(m)
        }

        let calendarManager = GoogleCalendarManager.shared
        let idList = Array(idSet)

        calendarManager.ensureCalendarWriteAccess { accessResult in
            DispatchQueue.main.async {
                switch accessResult {
                case .failure(let err):
                    completion(err)
                case .success:
                    calendarManager.deleteCalendarEventsSequentially(idList) { err in
                        DispatchQueue.main.async {
                            if let err = err {
                                completion(err)
                                return
                            }
                            for id in idList {
                                NotificationManager.shared.cancelJournalPromptNotification(eventId: id)
                                NotificationManager.shared.cancelPreTaskNotification(eventId: id)
                                firebaseManager.deleteScheduledEvent(eventId: id) { _ in }
                            }
                            for t in tasksToUnlink {
                                t.manualScheduleGoogleEventId = nil
                                t.scheduledStartTime = nil
                                t.scheduledEndTime = nil
                            }
                            try? modelContext.save()
                            for t in tasksToUnlink {
                                guard let userId = Auth.auth().currentUser?.uid else { continue }
                                let codable = TodoItemCodable(from: t, userId: userId)
                                firebaseManager.saveTodoItem(codable) { _ in }
                            }
                            refreshScreenTimeSnapshot(context: modelContext)
                            completion(nil)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private static func refreshScreenTimeSnapshot(context: ModelContext) {
        Task { @MainActor in
            ScreenTimeManager.shared.scheduleSnapshotRefresh(context: context)
        }
    }

    private static func clearLocalSchedule(for task: TodoItem) {
        task.manualScheduleGoogleEventId = nil
        task.scheduledStartTime = nil
        task.scheduledEndTime = nil
    }

    private static func syncTaskToFirebase(_ task: TodoItem, firebaseManager: FirebaseManager) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let codable = TodoItemCodable(from: task, userId: userId)
        firebaseManager.saveTodoItem(codable) { _ in }
    }

    /// Matches combined-event copy in `ManualSchedulingView.addToGoogleCalendar`.
    static func googleCalendarPayload(for tasks: [TodoItem]) -> (title: String, description: String) {
        let taskTitles = tasks.map(\.title)
        let title: String
        if taskTitles.count == 1, let only = taskTitles.first {
            title = only
        } else if let first = taskTitles.first {
            title = "\(first) and \(taskTitles.count - 1) more"
        } else {
            title = "YourDay tasks"
        }

        let combinedDetails = tasks
            .map(\.detail)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let scheduledTaskMarker = "\n\n[YourDay Scheduled Task]"
        let tasksList = taskTitles.map { "• \($0)" }.joined(separator: "\n")
        let description: String
        if combinedDetails.isEmpty {
            description = "Tasks:\n\(tasksList)\(scheduledTaskMarker)"
        } else {
            description = "Tasks:\n\(tasksList)\n\n\(combinedDetails)\(scheduledTaskMarker)"
        }
        return (title, description)
    }
}

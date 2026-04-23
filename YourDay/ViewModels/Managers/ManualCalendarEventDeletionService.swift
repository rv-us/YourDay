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
                            ScreenTimeManager.shared.scheduleSnapshotRefresh(context: modelContext)
                            completion(nil)
                        }
                    }
                }
            }
        }
    }
}

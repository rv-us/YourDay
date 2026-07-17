//
//  GroupTask.swift
//  YourDay
//
//  A task created inside a group chat and assigned to selected members.
//  Lives in the top-level `group_tasks` Firestore collection; progress is
//  aggregated via `completedBy` against `assigneeIds`.
//

import Foundation
import FirebaseFirestore

struct GroupTask: Identifiable, Codable {
    @DocumentID var id: String?
    var groupId: String
    var groupName: String
    var creatorId: String
    var creatorDisplayName: String
    var title: String
    var detail: String
    var dueDate: Date
    var assigneeIds: [String]
    /// uid -> display name, captured at creation time.
    var assigneeNames: [String: String]
    /// uids of assignees who have completed their local copy of the task.
    var completedBy: [String]
    /// uids whose device already created the local TodoItem; prevents re-adding
    /// after the user deletes the task locally or the daily cleanup removes it.
    var materializedBy: [String]
    var createdAt: Date
}

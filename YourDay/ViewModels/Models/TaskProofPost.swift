import Foundation
import FirebaseFirestore

enum TaskProofSourceType: String, Codable {
    case scheduled
    case unscheduled
    case shared
}

struct TaskProofPost: Identifiable, Codable {
    @DocumentID var id: String?
    let authorId: String
    let authorDisplayName: String
    let taskTitle: String
    let sourceType: TaskProofSourceType
    let scheduledEventId: String?
    let localTaskId: String?
    let sharedTaskId: String?
    let completedAt: Date
    let createdAt: Date
    let photoURL: String
    let photoStoragePath: String
}

struct TaskProofCaptureContext: Identifiable {
    var id: String { "\(taskTitle)-\(localTaskId)-\(completedAt.timeIntervalSince1970)" }
    let taskTitle: String
    let sourceType: TaskProofSourceType
    let scheduledEventId: String?
    let localTaskId: String?
    let sharedTaskId: String?
    let completedAt: Date
}

struct FriendWithSince: Identifiable {
    var id: String { userId }
    let userId: String
    let since: Date
}

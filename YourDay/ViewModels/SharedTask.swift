import Foundation
import FirebaseFirestore

struct SharedSubtask: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var isDone: Bool
}

struct SharedTask: Identifiable, Codable {
    @DocumentID var id: String? // Firestore auto-generated ID
    let senderId: String
    let receiverId: String
    var title: String
    var detail: String
    var dueDate: Date
    var isAccepted: Bool
    var isCompleted: Bool
    var createdAt: Date
    var completedAt: Date?
    var subtasks: [SharedSubtask] = []
} 
import Foundation
import FirebaseFirestore

enum TaskProofVoteType: String, Codable {
    case check
    case xmark
}

struct TaskProofVote: Identifiable, Codable {
    @DocumentID var id: String?
    let voterId: String
    let voterDisplayName: String
    let voteType: TaskProofVoteType
    let updatedAt: Date
}

import Foundation
import FirebaseFirestore

struct GroupConversation: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var adminId: String
    var memberIds: [String]
    var lastMessageText: String
    var lastMessageAt: Date
    var lastMessageSenderId: String
    var createdAt: Date
}

struct GroupMember: Identifiable, Codable {
    @DocumentID var id: String? // = userId
    var displayName: String
    var joinedAt: Date
    var role: String // "admin" | "member"
}

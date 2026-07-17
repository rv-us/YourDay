//
//  ChatMessage.swift
//  YourDay
//
//  Created by Rachit Verma on 8/2/25.
//

import Foundation
import FirebaseFirestore

struct ChatMessage: Identifiable, Codable {
    @DocumentID var id: String? // Firestore auto-generated ID
    let senderId: String
    let receiverId: String
    let content: String
    let timestamp: Date
    var groupId: String? = nil            // nil for DMs; set for group messages
    var senderDisplayName: String? = nil  // nil for DMs; set for group messages
    var kind: String? = nil               // nil = plain text; "group_task" | "proof_post"
    var refId: String? = nil              // groupTaskId or proofPostId, depending on kind
}

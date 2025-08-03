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
}

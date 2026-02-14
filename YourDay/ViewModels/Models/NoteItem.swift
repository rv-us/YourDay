//
//  NoteItem.swift
//  YourDay
//
//  Created by Ruthwika Gajjala on 4/27/25.
//

import Foundation
import SwiftData

@Model
class NoteItem {
    @Attribute(.unique) var id: UUID
    var content: String
    var createdAt: Date

    init(content: String) {
        self.id = UUID()
        self.content = content
        self.createdAt = Date()
    }
    
    init(id: UUID, content: String, createdAt: Date = Date()) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
    }
}


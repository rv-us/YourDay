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
    /// Display font size for the note (nil = default 17).
    var fontSize: Double?

    init(content: String, fontSize: Double? = nil) {
        self.id = UUID()
        self.content = content
        self.createdAt = Date()
        self.fontSize = fontSize
    }
    
    init(id: UUID, content: String, createdAt: Date = Date(), fontSize: Double? = nil) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.fontSize = fontSize
    }
}


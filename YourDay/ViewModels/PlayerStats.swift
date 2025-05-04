//
//  PlayerStats.swift
//  YourDay
//
//  Created by Rachit Verma on 5/4/25.
//

import Foundation
import SwiftData

@Model
class PlayerStats {
    var id: UUID = UUID()
    var totalPoints: Double
    var lastEvaluated: Date?

    init(totalPoints: Double = 0, lastEvaluated: Date? = nil) {
        self.totalPoints = totalPoints
        self.lastEvaluated = lastEvaluated
    }
}

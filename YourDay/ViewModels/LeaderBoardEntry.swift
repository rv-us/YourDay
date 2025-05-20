//
//  LeaderBoardEntry.swift
//  YourDay
//
//  Created by Rachit Verma on 5/20/25.
//
import Foundation

struct LeaderboardEntry: Identifiable, Codable {
    var id: String
    var rank: Int?
    var displayName: String
    var playerLevel: Int
    var gardenValue: Double

    enum CodingKeys: String, CodingKey {
        case id = "userID"
        case displayName
        case playerLevel
        case gardenValue
    }
}


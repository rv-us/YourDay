//
//  PlayerStatsCodeable.swift
//  YourDay
//
//  Created by Rachit Verma on 5/19/25.
//
import Foundation
import SwiftUI // For Color, though ideally Codable structs are data-only

// Ensure Rarity, PlantTheme, GridPosition, PlacedPlant are Codable.
// These should be defined as in your PlayerStats.swift.
// For example:
// enum Rarity: String, Codable { ... }
// struct PlacedPlant: Codable, Identifiable { ... }

struct PlayerStatsCodable: Codable, Identifiable {
    var id: UUID
    var totalPoints: Double
    var lastEvaluated: Date?
    var lastLoginDate: Date?
    var lastDailyPointsEarned: Double
    var lastDailyCompletedTasks: Int
    var lastDailyTotalTasks: Int
    var taskCompletionStreak: Int
    var playerLevel: Int
    var currentXP: Double
    var gardenValue: Double // This will now be taken from the model during conversion
    var unplacedPlantsInventory: [String: Int]
    var placedPlants: [PlacedPlant]
    var numberOfOwnedPlots: Int
    var fertilizerCount: Int
    
    // Schema version for future migrations
    var schemaVersion: Int = 2

    // Default initializer for new users (matches PlayerStats @Model default)
    init(
        id: UUID = UUID(),
        totalPoints: Double = 100,
        lastEvaluated: Date? = nil,
        lastLoginDate: Date? = Calendar.current.startOfDay(for:Date()),
        lastDailyPointsEarned: Double = 0,
        lastDailyCompletedTasks: Int = 0,
        lastDailyTotalTasks: Int = 0,
        taskCompletionStreak: Int = 0,
        playerLevel: Int = 1,
        currentXP: Double = 0,
        unplacedPlantsInventory: [String: Int] = [:],
        placedPlants: [PlacedPlant] = [], // Ensure PlacedPlant has its getCurrentDynamicValue()
        numberOfOwnedPlots: Int = 2,
        fertilizerCount: Int = 1,
        schemaVersion: Int = 3
    ) {
        self.id = id
        self.totalPoints = totalPoints
        self.lastEvaluated = lastEvaluated
        self.lastLoginDate = lastLoginDate
        self.lastDailyPointsEarned = lastDailyPointsEarned
        self.lastDailyCompletedTasks = lastDailyCompletedTasks
        self.lastDailyTotalTasks = lastDailyTotalTasks
        self.taskCompletionStreak = taskCompletionStreak
        self.playerLevel = playerLevel
        self.currentXP = currentXP
        self.unplacedPlantsInventory = unplacedPlantsInventory
        self.placedPlants = placedPlants
        self.numberOfOwnedPlots = numberOfOwnedPlots
        self.fertilizerCount = fertilizerCount
        self.schemaVersion = schemaVersion
        
        // Calculate gardenValue based on placedPlants for a new Codable instance
        var calculatedGardenValue: Double = 0.0
        for plant in self.placedPlants {
            // Assuming PlacedPlant has getCurrentDynamicValue which checks if it's fully grown
            calculatedGardenValue += plant.getCurrentDynamicValue()
        }
        self.gardenValue = calculatedGardenValue
    }

    // Initializer to convert from SwiftData PlayerStats @Model
    init(from model: PlayerStats) {
        self.id = model.id // Assuming PlayerStats @Model has a UUID id
        self.totalPoints = model.totalPoints
        self.lastEvaluated = model.lastEvaluated
        self.lastLoginDate = model.lastLoginDate
        self.lastDailyPointsEarned = model.lastDailyPointsEarned
        self.lastDailyCompletedTasks = model.lastDailyCompletedTasks
        self.lastDailyTotalTasks = model.lastDailyTotalTasks
        self.taskCompletionStreak = model.taskCompletionStreak
        self.playerLevel = model.playerLevel
        self.currentXP = model.currentXP
        self.gardenValue = model.gardenValue // Take the calculated value from the model
        self.unplacedPlantsInventory = model.unplacedPlantsInventory
        self.placedPlants = model.placedPlants // Assumes PlacedPlant struct is Codable
        self.numberOfOwnedPlots = model.numberOfOwnedPlots
        self.fertilizerCount = model.fertilizerCount
        self.schemaVersion = 3 // Current schema version
    }
    
    // Custom decoding to handle schema migrations
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Try to decode schema version, default to 0 if not present (old data)
        let version = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        
        // Decode all other properties
        id = try container.decode(UUID.self, forKey: .id)
        totalPoints = try container.decode(Double.self, forKey: .totalPoints)
        lastEvaluated = try container.decodeIfPresent(Date.self, forKey: .lastEvaluated)
        lastLoginDate = try container.decodeIfPresent(Date.self, forKey: .lastLoginDate)
        lastDailyPointsEarned = try container.decodeIfPresent(Double.self, forKey: .lastDailyPointsEarned) ?? 0
        lastDailyCompletedTasks = try container.decodeIfPresent(Int.self, forKey: .lastDailyCompletedTasks) ?? 0
        lastDailyTotalTasks = try container.decodeIfPresent(Int.self, forKey: .lastDailyTotalTasks) ?? 0
        taskCompletionStreak = try container.decodeIfPresent(Int.self, forKey: .taskCompletionStreak) ?? 0
        playerLevel = try container.decode(Int.self, forKey: .playerLevel)
        currentXP = try container.decode(Double.self, forKey: .currentXP)
        gardenValue = try container.decode(Double.self, forKey: .gardenValue)
        unplacedPlantsInventory = try container.decode([String: Int].self, forKey: .unplacedPlantsInventory)
        placedPlants = try container.decode([PlacedPlant].self, forKey: .placedPlants)
        numberOfOwnedPlots = try container.decode(Int.self, forKey: .numberOfOwnedPlots)
        fertilizerCount = try container.decode(Int.self, forKey: .fertilizerCount)
        
        // Apply schema migrations if needed
        if version < 3 {
            // Migrate 1D grid positions to 2D island grid
            let allOldFormat = placedPlants.allSatisfy { $0.position.y == 0 }
            if allOldFormat && !placedPlants.isEmpty {
                let unlockOrder = IslandGridConfig.tileUnlockOrder
                for i in placedPlants.indices {
                    let oldIndex = placedPlants[i].position.x
                    if oldIndex >= 0 && oldIndex < unlockOrder.count {
                        placedPlants[i].position = unlockOrder[oldIndex]
                    } else if i < unlockOrder.count {
                        placedPlants[i].position = unlockOrder[i]
                    }
                }
            }
        }

        schemaVersion = 3
    }
    
    // Custom encoding to ensure schema version is always included
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(totalPoints, forKey: .totalPoints)
        try container.encodeIfPresent(lastEvaluated, forKey: .lastEvaluated)
        try container.encodeIfPresent(lastLoginDate, forKey: .lastLoginDate)
        try container.encode(lastDailyPointsEarned, forKey: .lastDailyPointsEarned)
        try container.encode(lastDailyCompletedTasks, forKey: .lastDailyCompletedTasks)
        try container.encode(lastDailyTotalTasks, forKey: .lastDailyTotalTasks)
        try container.encode(taskCompletionStreak, forKey: .taskCompletionStreak)
        try container.encode(playerLevel, forKey: .playerLevel)
        try container.encode(currentXP, forKey: .currentXP)
        try container.encode(gardenValue, forKey: .gardenValue)
        try container.encode(unplacedPlantsInventory, forKey: .unplacedPlantsInventory)
        try container.encode(placedPlants, forKey: .placedPlants)
        try container.encode(numberOfOwnedPlots, forKey: .numberOfOwnedPlots)
        try container.encode(fertilizerCount, forKey: .fertilizerCount)
        try container.encode(schemaVersion, forKey: .schemaVersion)
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, totalPoints, lastEvaluated, lastLoginDate
        case lastDailyPointsEarned, lastDailyCompletedTasks, lastDailyTotalTasks, taskCompletionStreak
        case playerLevel, currentXP
        case gardenValue, unplacedPlantsInventory, placedPlants, numberOfOwnedPlots, fertilizerCount, schemaVersion
    }

    // Method to convert this Codable struct to a SwiftData PlayerStats @Model
    // This is used when loading data from Firestore and populating/updating SwiftData.
    // The actual insertion/update into ModelContext happens where this is called.
    func toPlayerStatsModelProperties() -> (
        id: UUID, totalPoints: Double, lastEvaluated: Date?, lastLoginDate: Date?,
        lastDailyPointsEarned: Double, lastDailyCompletedTasks: Int, lastDailyTotalTasks: Int, taskCompletionStreak: Int,
                playerLevel: Int, currentXP: Double,
        gardenValue: Double, unplacedPlantsInventory: [String: Int], placedPlants: [PlacedPlant],
        numberOfOwnedPlots: Int, fertilizerCount: Int
    ) {
        return (
            id: self.id,
            totalPoints: self.totalPoints,
            lastEvaluated: self.lastEvaluated,
            lastLoginDate: self.lastLoginDate,
            lastDailyPointsEarned: self.lastDailyPointsEarned,
            lastDailyCompletedTasks: self.lastDailyCompletedTasks,
            lastDailyTotalTasks: self.lastDailyTotalTasks,
            taskCompletionStreak: self.taskCompletionStreak,
            playerLevel: self.playerLevel,
            currentXP: self.currentXP,
            gardenValue: self.gardenValue, 
            unplacedPlantsInventory: self.unplacedPlantsInventory,
            placedPlants: self.placedPlants,
            numberOfOwnedPlots: self.numberOfOwnedPlots,
            fertilizerCount: self.fertilizerCount
        )
    }
}

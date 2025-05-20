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
    var playerLevel: Int
    var currentXP: Double
    var gardenValue: Double // This will now be taken from the model during conversion
    var unplacedPlantsInventory: [String: Int]
    var placedPlants: [PlacedPlant]
    var numberOfOwnedPlots: Int
    var fertilizerCount: Int

    // Default initializer for new users (matches PlayerStats @Model default)
    init(
        id: UUID = UUID(),
        totalPoints: Double = 1000,
        lastEvaluated: Date? = nil,
        playerLevel: Int = 1,
        currentXP: Double = 0,
        unplacedPlantsInventory: [String: Int] = [:],
        placedPlants: [PlacedPlant] = [], // Ensure PlacedPlant has its getCurrentDynamicValue()
        numberOfOwnedPlots: Int = 2,
        fertilizerCount: Int = 3
    ) {
        self.id = id
        self.totalPoints = totalPoints
        self.lastEvaluated = lastEvaluated
        self.playerLevel = playerLevel
        self.currentXP = currentXP
        self.unplacedPlantsInventory = unplacedPlantsInventory
        self.placedPlants = placedPlants
        self.numberOfOwnedPlots = numberOfOwnedPlots
        self.fertilizerCount = fertilizerCount
        
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
        self.playerLevel = model.playerLevel
        self.currentXP = model.currentXP
        self.gardenValue = model.gardenValue // Take the calculated value from the model
        self.unplacedPlantsInventory = model.unplacedPlantsInventory
        self.placedPlants = model.placedPlants // Assumes PlacedPlant struct is Codable
        self.numberOfOwnedPlots = model.numberOfOwnedPlots
        self.fertilizerCount = model.fertilizerCount
    }

    // Method to convert this Codable struct to a SwiftData PlayerStats @Model
    // This is used when loading data from Firestore and populating/updating SwiftData.
    // The actual insertion/update into ModelContext happens where this is called.
    func toPlayerStatsModelProperties() -> (
        id: UUID, totalPoints: Double, lastEvaluated: Date?, playerLevel: Int, currentXP: Double,
        gardenValue: Double, unplacedPlantsInventory: [String: Int], placedPlants: [PlacedPlant],
        numberOfOwnedPlots: Int, fertilizerCount: Int
    ) {
        return (
            id: self.id, // Pass the ID for potential matching
            totalPoints: self.totalPoints,
            lastEvaluated: self.lastEvaluated,
            playerLevel: self.playerLevel,
            currentXP: self.currentXP,
            gardenValue: self.gardenValue, // Use the value from Firestore
            unplacedPlantsInventory: self.unplacedPlantsInventory,
            placedPlants: self.placedPlants,
            numberOfOwnedPlots: self.numberOfOwnedPlots,
            fertilizerCount: self.fertilizerCount
        )
    }
}

//
//  PlayerStats.swift
//  YourDay
//
//  Created by Rachit Verma on 5/4/25.
//

import Foundation
import SwiftData

// Helper struct for storing grid coordinates.
// Conforms to Codable to be storable by SwiftData within PlacedPlant.
struct GridPosition: Codable, Hashable {
    var x: Int
    var y: Int
}

// Helper struct for representing a plant placed in the garden.
// Conforms to Codable to be storable by SwiftData as part of an array in PlayerStats.
struct PlacedPlant: Codable, Identifiable, Hashable {
    var id = UUID() // Identifiable for potential list rendering
    var name: String // Name/type of the plant
    var position: GridPosition // Where it's placed on the grid
    var plantedDate: Date // When the plant was placed
    var lastWateredDate: Date? // To track watering needs

    // You might add more properties here later, like growth stage, current value, etc.
    init(name: String, position: GridPosition, plantedDate: Date = Date(), lastWateredDate: Date? = nil) {
        self.name = name
        self.position = position
        self.plantedDate = plantedDate
        self.lastWateredDate = lastWateredDate
    }
}

@Model
class PlayerStats {
    // Existing properties
    var id: UUID = UUID()
    var totalPoints: Double // Currency earned from tasks, might be used for gambling
    var lastEvaluated: Date?

    // New Gamification Properties
    var playerLevel: Int
    var gardenValue: Double // Base value of the garden + value of placed plants
    
    // Inventory of plants not yet placed in the garden.
    // Key: Plant Type/Name (String), Value: Quantity (Int)
    var unplacedPlantsInventory: [String: Int]
    
    // Plants that are currently placed in the garden grid.
    var placedPlants: [PlacedPlant]
    
    // It's good practice to provide an initializer, especially with default values.
    init(
        totalPoints: Double = 0,
        lastEvaluated: Date? = nil,
        playerLevel: Int = 1, // Start at level 1
        gardenValue: Double = 100.0, // Base garden value
        unplacedPlantsInventory: [String: Int] = [:], // Empty inventory initially
        placedPlants: [PlacedPlant] = [] // No plants placed initially
    ) {
        self.id = UUID() // Ensure ID is always initialized
        self.totalPoints = totalPoints
        self.lastEvaluated = lastEvaluated
        self.playerLevel = playerLevel
        self.gardenValue = gardenValue
        self.unplacedPlantsInventory = unplacedPlantsInventory
        self.placedPlants = placedPlants
    }
}

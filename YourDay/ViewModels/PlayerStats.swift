//
//  PlayerStats.swift
//  YourDay
//
//  Created by Rachit Verma on 5/4/25.
//

import Foundation
import SwiftData

// Enum for Plant Rarity
enum Rarity: String, Codable, CaseIterable, Hashable {
    case common = "Common"
    case rare = "Rare"
    case epic = "Epic"
    case legendary = "Legendary"
}

// Enum for Plant Theme/Season
enum PlantTheme: String, Codable, CaseIterable, Hashable {
    case spring = "Spring"
    case summer = "Summer"
    case fall = "Fall"
    case winter = "Winter"
    // Removed Mystical and Elemental as they were not in the user-provided current version of the immersive
}

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
    var name: String // Name/type of the plant, e.g., "Sunflower"
    var position: GridPosition // Where it's placed on the grid
    var plantedDate: Date // When the plant was placed
    
    // New growth mechanic properties
    var daysLeftTillFullyGrown: Int // Days remaining until the plant is mature
    var lastWateredOnDay: Date? // Tracks the start of the day when the plant was last watered

    // New descriptive properties
    var rarity: Rarity
    var theme: PlantTheme
    // This baseValue is used for calculating sell price.
    var baseValue: Double

    // Computed property to check if the plant is fully grown
    var isFullyGrown: Bool {
        return daysLeftTillFullyGrown <= 0
    }

    // Initializer updated for the new growth mechanic and descriptive properties
    init(name: String,
         position: GridPosition,
         initialDaysToGrow: Int,
         rarity: Rarity,
         theme: PlantTheme,
         baseValue: Double,
         plantedDate: Date = Date(),
         lastWateredOnDay: Date? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.position = position
        self.plantedDate = plantedDate
        self.daysLeftTillFullyGrown = initialDaysToGrow
        self.lastWateredOnDay = lastWateredOnDay
        self.rarity = rarity
        self.theme = theme
        self.baseValue = baseValue
    }
    
    // Example method to water the plant
    mutating func waterPlant() {
        let today = Calendar.current.startOfDay(for: Date())
        
        if !isFullyGrown && (lastWateredOnDay == nil || !Calendar.current.isDate(lastWateredOnDay!, inSameDayAs: today)) {
            if daysLeftTillFullyGrown > 0 {
                daysLeftTillFullyGrown -= 1
            }
            lastWateredOnDay = today
            print("\(name) (\(rarity.rawValue), \(theme.rawValue)) at \(position.x),\(position.y) watered. Days left: \(daysLeftTillFullyGrown)")
        } else if isFullyGrown {
            print("\(name) at \(position.x),\(position.y) is already fully grown.")
        } else {
            print("\(name) at \(position.x),\(position.y) was already watered today.")
        }
    }
    
    // Helper function to determine the current season
    private func getCurrentSeason(from date: Date = Date()) -> PlantTheme? {
        let month = Calendar.current.component(.month, from: date)
        switch month {
        case 3, 4, 5: // March, April, May
            return .spring
        case 6, 7, 8: // June, July, August
            return .summer
        case 9, 10, 11: // September, October, November
            return .fall
        case 12, 1, 2: // December, January, February
            return .winter
        default:
            return nil // Should not happen
        }
    }
    
    // Method to get current value, now based on rarity and season if fully grown.
    func getCurrentValue() -> Double {
        guard isFullyGrown else {
            return 0 // Value is 0 if not fully grown
        }

        var calculatedValue: Double
        switch rarity {
        case .common:
            calculatedValue = 50.0
        case .rare:
            calculatedValue = 250.0
        case .epic:
            calculatedValue = 500.0
        case .legendary:
            calculatedValue = 1000.0
        }
        
        // Apply seasonal bonus
        if let currentSeason = getCurrentSeason() {
            if self.theme == currentSeason {
                calculatedValue *= 2
                print("Seasonal bonus applied for \(name)! Current value: \(calculatedValue)")
            }
        }
        
        return calculatedValue
    }
}

@Model
class PlayerStats {
    // Existing properties
    var id: UUID = UUID()
    var totalPoints: Double
    var lastEvaluated: Date?

    // Gamification Properties
    var playerLevel: Int
    var gardenValue: Double // This will be a calculated sum of all placed, grown plants' values
    
    var unplacedPlantsInventory: [String: Int] // Key: Plant Name (which implies its type, rarity, theme)
    var placedPlants: [PlacedPlant]
    
    init(
        totalPoints: Double = 0,
        lastEvaluated: Date? = nil,
        playerLevel: Int = 1,
        gardenValue: Double = 100.0, // Initial base value of the plot itself perhaps
        unplacedPlantsInventory: [String: Int] = [:],
        placedPlants: [PlacedPlant] = []
    ) {
        self.id = UUID()
        self.totalPoints = totalPoints
        self.lastEvaluated = lastEvaluated
        self.playerLevel = playerLevel
        self.gardenValue = gardenValue
        self.unplacedPlantsInventory = unplacedPlantsInventory
        self.placedPlants = placedPlants
    }
    
    // Method to recalculate total garden value
    func updateGardenValue() {
        var calculatedTotalGardenValue = 100.0 // Start with the base value of the garden plot itself
        for plant in placedPlants {
            calculatedTotalGardenValue += plant.getCurrentValue()
        }
        self.gardenValue = calculatedTotalGardenValue
        print("Garden value updated to: \(self.gardenValue)")
    }

    // New method to sell/delete a plant
    // Returns true if successful, false if plant not found
    func sellPlant(plantId: UUID) -> Bool {
        // Find the index of the plant to be sold
        if let plantIndex = placedPlants.firstIndex(where: { $0.id == plantId }) {
            let plantToSell = placedPlants[plantIndex]
            
            // Calculate sell price: 1.5 times the plant's baseValue
            // The problem states "base value", so we use plantToSell.baseValue directly,
            // not the potentially seasonally-adjusted getCurrentValue().
            let sellPrice = plantToSell.baseValue * 1.5
            
            // Add sell price to player's total points
            self.totalPoints += sellPrice
            
            // Remove the plant from the placedPlants array
            placedPlants.remove(at: plantIndex)
            
            // Update the garden value
            updateGardenValue()
            
            print("Sold plant '\(plantToSell.name)' for \(sellPrice) points. Player total points: \(self.totalPoints)")
            return true
        } else {
            print("Could not sell plant: Plant with ID \(plantId) not found.")
            return false
        }
    }
}

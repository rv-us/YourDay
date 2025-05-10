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
    case uncommon = "Uncommon"
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
}

// Helper struct for storing grid coordinates.
struct GridPosition: Codable, Hashable {
    var x: Int
    var y: Int
}

// Helper struct for representing a plant placed in the garden.
struct PlacedPlant: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var position: GridPosition
    var plantedDate: Date
    var daysLeftTillFullyGrown: Int
    var lastWateredOnDay: Date?
    var rarity: Rarity
    var theme: PlantTheme
    var baseValue: Double

    var isFullyGrown: Bool {
        return daysLeftTillFullyGrown <= 0
    }

    init(name: String, position: GridPosition, initialDaysToGrow: Int, rarity: Rarity, theme: PlantTheme, baseValue: Double, plantedDate: Date = Date(), lastWateredOnDay: Date? = nil) {
        self.id = UUID() // Ensure ID is always initialized
        self.name = name
        self.position = position
        self.plantedDate = plantedDate
        self.daysLeftTillFullyGrown = initialDaysToGrow
        self.lastWateredOnDay = lastWateredOnDay
        self.rarity = rarity
        self.theme = theme
        self.baseValue = baseValue
    }

    mutating func waterPlant() {
        let today = Calendar.current.startOfDay(for: Date())
        if !isFullyGrown && (lastWateredOnDay == nil || !Calendar.current.isDate(lastWateredOnDay!, inSameDayAs: today)) {
            if daysLeftTillFullyGrown > 0 { daysLeftTillFullyGrown -= 1 }
            lastWateredOnDay = today
            // Log includes more details now
            print("\(name) (\(rarity.rawValue), \(theme.rawValue)) at \(position.x),\(position.y) watered. Days left: \(daysLeftTillFullyGrown)")
        } else if isFullyGrown {
            print("\(name) at \(position.x),\(position.y) is already fully grown.")
        } else {
            print("\(name) at \(position.x),\(position.y) was already watered today.")
        }
    }

    private func getCurrentSeason(from date: Date = Date()) -> PlantTheme? {
        let month = Calendar.current.component(.month, from: date)
        switch month {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .fall
        case 12, 1, 2: return .winter
        default: return nil
        }
    }

    func getCurrentValue() -> Double {
        guard isFullyGrown else { return 0 }
        var calculatedValue: Double
        switch rarity {
        case .common: calculatedValue = 50.0
        case .uncommon: calculatedValue = 150.0 // Value for uncommon
        case .rare: calculatedValue = 250.0
        case .epic: calculatedValue = 500.0
        case .legendary: calculatedValue = 1000.0
        }
        if let currentSeason = getCurrentSeason(), self.theme == currentSeason {
            calculatedValue *= 2
            // Log seasonal bonus
            // print("Seasonal bonus applied for \(name)! Current value: \(calculatedValue)")
        }
        return calculatedValue
    }
}

@Model
class PlayerStats {
    var id: UUID = UUID()
    var totalPoints: Double // Acts as currency
    var lastEvaluated: Date?

    // Gamification Properties
    var playerLevel: Int
    var currentXP: Double // XP accumulated towards the next level
    var gardenValue: Double
    var unplacedPlantsInventory: [String: Int]
    var placedPlants: [PlacedPlant]
    var numberOfOwnedPlots: Int // Number of plots the player currently owns

    init(
        totalPoints: Double = 0,
        lastEvaluated: Date? = nil,
        playerLevel: Int = 1,
        currentXP: Double = 0, // Initialize currentXP
        gardenValue: Double = 100.0,
        unplacedPlantsInventory: [String: Int] = [:],
        placedPlants: [PlacedPlant] = [],
        numberOfOwnedPlots: Int = 2 // Start with 2 plots by default
    ) {
        self.id = UUID()
        self.totalPoints = totalPoints
        self.lastEvaluated = lastEvaluated
        self.playerLevel = playerLevel
        self.currentXP = currentXP
        self.gardenValue = gardenValue
        self.unplacedPlantsInventory = unplacedPlantsInventory
        self.placedPlants = placedPlants
        self.numberOfOwnedPlots = numberOfOwnedPlots
    }

    // --- Leveling System ---
    /// Calculates the XP needed to complete the `currentLevel` and advance to `currentLevel + 1`.
    static func xpRequiredForNextLevel(currentLevel: Int) -> Double {
        if currentLevel <= 0 { return 100.0 } // Default for safety if an invalid level is passed

        switch currentLevel {
        case 1:
            return 100.0 // XP to complete Level 1 (to reach Level 2)
        case 2:
            return 150.0 // XP to complete Level 2 (to reach Level 3)
        case 3:
            return 200.0 // XP to complete Level 3 (to reach Level 4)
        case 4:
            return 250.0 // XP to complete Level 4 (to reach Level 5)
        default: // For currentLevel 5 and above
            let baseXpForLevel5: Double = 500.0
            let scalingFactor: Double = 2 
            if currentLevel == 5 {
                return baseXpForLevel5
            } else {
                // Calculate for levels 6 and above
                return round(baseXpForLevel5 * pow(scalingFactor, Double(currentLevel - 5)))
            }
        }
    }
    
    /// Returns the total XP accumulated to reach the start of the given level.
    /// (Not strictly needed for current logic but can be useful for display)
    static func totalXpToReachLevel(_ level: Int) -> Double {
        guard level > 1 else { return 0 }
        var totalXP: Double = 0
        for i in 1..<level { // Sum XP required for all previous levels
            totalXP += xpRequiredForNextLevel(currentLevel: i)
        }
        return totalXP
    }

    @discardableResult
    func addXP(_ points: Double) -> (didLevelUp: Bool, newLevel: Int, newXP: Double) {
        guard points > 0 else { return (false, self.playerLevel, self.currentXP) }
        var newXP = self.currentXP + points
        var currentLevelRequirement = PlayerStats.xpRequiredForNextLevel(currentLevel: self.playerLevel)
        var didLevelUpThisCycle = false
        while newXP >= currentLevelRequirement {
            self.playerLevel += 1
            newXP -= currentLevelRequirement
            didLevelUpThisCycle = true
            print("🎉 LEVEL UP! Reached Level \(self.playerLevel). Excess XP: \(newXP)")
            currentLevelRequirement = PlayerStats.xpRequiredForNextLevel(currentLevel: self.playerLevel)
        }
        self.currentXP = newXP
        return (didLevelUpThisCycle, self.playerLevel, self.currentXP)
    }

    // --- Garden Plot System ---
    var maxPlotsForCurrentLevel: Int {
        // Level 1 starts with 2 plots. Each level up adds 3 potential plot purchases.
        return 2 + (self.playerLevel - 1) * 3
    }

    func costToBuyNextPlot() -> Double {
        // Cost scales with the player's current level
        return 20.0 * Double(self.playerLevel)
    }

    @discardableResult
    func buyNextPlot() -> Bool {
        let cost = costToBuyNextPlot()
        if numberOfOwnedPlots < maxPlotsForCurrentLevel && totalPoints >= cost {
            totalPoints -= cost
            numberOfOwnedPlots += 1
            print("Plot purchased! Owned plots: \(numberOfOwnedPlots). Points left: \(totalPoints)")
            return true
        } else {
            if numberOfOwnedPlots >= maxPlotsForCurrentLevel {
                print("Cannot buy plot: Already at max plots for current level (\(maxPlotsForCurrentLevel)).")
            }
            if totalPoints < cost {
                print("Cannot buy plot: Insufficient points. Need \(cost), have \(totalPoints).")
            }
            return false
        }
    }

    // --- Other Methods ---
    func updateGardenValue() {
        var calculatedTotalGardenValue = 100.0 // Base value of the garden plot itself
        for plant in placedPlants {
            calculatedTotalGardenValue += plant.getCurrentValue()
        }
        self.gardenValue = calculatedTotalGardenValue
        // print("Garden value updated to: \(self.gardenValue)") // Optional log
    }

    func sellPlant(plantId: UUID) -> Bool {
        if let plantIndex = placedPlants.firstIndex(where: { $0.id == plantId }) {
            let plantToSell = placedPlants[plantIndex]
            let sellPrice = plantToSell.baseValue * 1.5 // Sell price based on plant's baseValue
            self.totalPoints += sellPrice
            placedPlants.remove(at: plantIndex)
            updateGardenValue() // Recalculate garden value after selling
            // print("Sold plant '\(plantToSell.name)' for \(sellPrice) points. Player total points: \(self.totalPoints)") // Optional log
            return true
        }
        // print("Could not sell plant: Plant with ID \(plantId) not found.") // Optional log
        return false
    }
}

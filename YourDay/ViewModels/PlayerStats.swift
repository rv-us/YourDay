//
//  PlayerStats.swift
//  YourDay
//
//  Created by Rachit Verma on 5/4/25.
//

import Foundation
import SwiftData
import SwiftUI // Import SwiftUI for Color

// Enum for Plant Rarity
enum Rarity: String, Codable, CaseIterable, Hashable {
    case common = "Common"
    case uncommon = "Uncommon"
    case rare = "Rare"
    case epic = "Epic"
    case legendary = "Legendary"

    // Color for text or distinct visual elements
    var textColor: Color {
        switch self {
        case .common: return .gray
        case .uncommon: return .green
        case .rare: return .blue
        case .epic: return .purple
        case .legendary: return .orange
        }
    }

    // Color for backgrounds (potentially with opacity)
    var backgroundColor: Color {
        switch self {
        case .common:   return Color.gray.opacity(0.3)
        case .uncommon: return Color.green.opacity(0.3)
        case .rare:     return Color.blue.opacity(0.3)
        case .epic:     return Color.purple.opacity(0.3)
        case .legendary: return Color.orange.opacity(0.3)
        }
    }
}

// Enum for Plant Theme/Season
enum PlantTheme: String, Codable, CaseIterable, Hashable {
    case spring = "Spring"
    case summer = "Summer"
    case fall = "Fall"
    case winter = "Winter"

    // Example color property
    var color: Color {
        switch self {
        case .spring: return .pink
        case .summer: return Color.yellow // Changed from .yellow to Color.yellow
        case .fall:   return .orange
        case .winter: return Color.blue
        }
    }
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
    var assetName: String
    var iconName: String
    var initialDaysToGrow: Int

    var isFullyGrown: Bool {
        return daysLeftTillFullyGrown <= 0
    }

    init(name: String, position: GridPosition, initialDaysToGrow: Int, rarity: Rarity, theme: PlantTheme, baseValue: Double, assetName: String, iconName: String, plantedDate: Date = Date(), lastWateredOnDay: Date? = nil) {
        self.id = UUID()
        self.name = name
        self.position = position
        self.plantedDate = plantedDate
        self.initialDaysToGrow = initialDaysToGrow
        self.daysLeftTillFullyGrown = initialDaysToGrow
        self.lastWateredOnDay = lastWateredOnDay
        self.rarity = rarity
        self.theme = theme
        self.baseValue = baseValue
        self.assetName = assetName
        self.iconName = iconName
    }

    mutating func waterPlant() {
        let today = Calendar.current.startOfDay(for: Date())
        if !isFullyGrown && (lastWateredOnDay == nil || !Calendar.current.isDate(lastWateredOnDay!, inSameDayAs: today)) {
            if daysLeftTillFullyGrown > 0 {
                daysLeftTillFullyGrown -= 1
            }
            lastWateredOnDay = today
        }
    }

    // Made public static so it can be accessed from elsewhere if needed, or keep private if only used internally
    static func getCurrentSeason(from date: Date = Date()) -> PlantTheme? {
        let month = Calendar.current.component(.month, from: date)
        switch month {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .fall
        case 12, 1, 2: return .winter
        default: return nil
        }
    }
    
    var themeBonusDetails: (isActive: Bool, multiplier: Double, currentSeason: PlantTheme?) {
        guard let currentSeason = PlacedPlant.getCurrentSeason() else {
            return (false, 1.0, nil)
        }
        if self.isFullyGrown && self.theme == currentSeason {
            return (true, 1.5, currentSeason) // 2.0x multiplier as per getCurrentDynamicValue
        }
        return (false, 1.0, currentSeason)
    }
    
    func getCurrentDynamicValue() -> Double {
        guard isFullyGrown else { return baseValue } // Return base value if not grown, or 0 if preferred
        
        var calculatedValue: Double
        // Using baseValue as the foundation for rarity scaling if plant is grown
        switch rarity {
        case .common:   calculatedValue = baseValue 
        case .uncommon: calculatedValue = baseValue
        case .rare:     calculatedValue = baseValue
        case .epic:     calculatedValue = baseValue
        case .legendary:calculatedValue = baseValue
        }
        
        if themeBonusDetails.isActive {
            calculatedValue *= themeBonusDetails.multiplier
        }
        return round(calculatedValue)
    }

    mutating func makeFullyGrown() {
        if !isFullyGrown {
            self.daysLeftTillFullyGrown = 0
        }
    }
}

@Model
class PlayerStats {
    var id: UUID = UUID()
    var totalPoints: Double
    var lastEvaluated: Date?

    var playerLevel: Int
    var currentXP: Double
    var gardenValue: Double
    var unplacedPlantsInventory: [String: Int]
    var placedPlants: [PlacedPlant]
    var numberOfOwnedPlots: Int
    var fertilizerCount: Int

    init(
        totalPoints: Double = 1000,
        lastEvaluated: Date? = nil,
        playerLevel: Int = 1,
        currentXP: Double = 0,
        unplacedPlantsInventory: [String: Int] = [:],
        placedPlants: [PlacedPlant] = [],
        numberOfOwnedPlots: Int = 2,
        fertilizerCount: Int = 3
    ) {
        self.id = UUID()
        self.totalPoints = totalPoints
        self.lastEvaluated = lastEvaluated
        self.playerLevel = playerLevel
        self.currentXP = currentXP
        self.gardenValue = 0
        self.unplacedPlantsInventory = unplacedPlantsInventory
        self.placedPlants = placedPlants
        self.numberOfOwnedPlots = numberOfOwnedPlots
        self.fertilizerCount = fertilizerCount
        updateGardenValue()
    }

    static func xpRequiredForNextLevel(currentLevel: Int) -> Double {
        if currentLevel <= 0 { return 100.0 }
        switch currentLevel {
        case 1: return 100.0
        case 2: return 300.0
        case 3: return 400.0
        case 4: return 500.0
        default:
            let baseXpForLevel5: Double = 300.0
            let scalingFactor: Double = 2
            if currentLevel == 5 {
                return baseXpForLevel5
            } else {
                return round(baseXpForLevel5 * pow(scalingFactor, Double(currentLevel - 5)))
            }
        }
    }

    static func totalXpToReachLevel(_ level: Int) -> Double {
        guard level > 1 else { return 0 }
        var totalXPAccumulated: Double = 0
        for i in 1..<level {
            totalXPAccumulated += xpRequiredForNextLevel(currentLevel: i)
        }
        return totalXPAccumulated
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
            currentLevelRequirement = PlayerStats.xpRequiredForNextLevel(currentLevel: self.playerLevel)
        }
        self.currentXP = newXP
        return (didLevelUpThisCycle, self.playerLevel, self.currentXP)
    }

    var maxPlotsForCurrentLevel: Int {
        if self.playerLevel == 1 {
            return 3
        } else {
            return self.playerLevel * 3
        }
    }

    func costToBuyNextPlot() -> Double {
        return 20.0 * Double(self.playerLevel)
    }

    @discardableResult
    func buyNextPlot() -> Bool {
        let cost = costToBuyNextPlot()
        if numberOfOwnedPlots < maxPlotsForCurrentLevel && totalPoints >= cost {
            totalPoints -= cost
            numberOfOwnedPlots += 1
            return true
        }
        return false
    }

    func pullPlants(forTheme theme: PlantTheme, numberOfPulls: Int, totalCost: Double) -> (success: Bool, pulledPlants: [PlantBlueprint], message: String) {
        guard totalPoints >= totalCost else {
            return (false, [], "Not enough points. Need \(Int(totalCost)), have \(Int(totalPoints)).")
        }

        var pulledBlueprints: [PlantBlueprint] = []
        let themeSpecificBlueprints = PlantLibrary.allPlantBlueprints.filter { $0.theme == theme }

        guard !themeSpecificBlueprints.isEmpty else {
            return (false, [], "No plants available for the \(theme.rawValue) theme in the library.")
        }

        for i in 0..<numberOfPulls {
            var chosenBlueprint: PlantBlueprint?
            let isGuaranteedPullSlot = (numberOfPulls == 10 && i == numberOfPulls - 1)

            if isGuaranteedPullSlot {
                chosenBlueprint = getGuaranteedRareOrBetterPlant(theme: theme, themeSpecificBlueprints: themeSpecificBlueprints)
            } else {
                let randomPercent = Double.random(in: 0..<100)
                var selectedRarity: Rarity
                if randomPercent < 60.0 { selectedRarity = .common }
                else if randomPercent < 85.0 { selectedRarity = .uncommon }
                else if randomPercent < 95.0 { selectedRarity = .rare }
                else if randomPercent < 99.0 { selectedRarity = .epic }
                else { selectedRarity = .legendary }
                chosenBlueprint = getPlantByRarity(theme: theme, rarity: selectedRarity, themeSpecificBlueprints: themeSpecificBlueprints)
            }
            
            if let plant = chosenBlueprint {
                pulledBlueprints.append(plant)
                unplacedPlantsInventory[plant.id, default: 0] += 1
            } else {
                if let fallbackPlant = themeSpecificBlueprints.filter({ $0.rarity == .common }).randomElement() {
                    pulledBlueprints.append(fallbackPlant)
                    unplacedPlantsInventory[fallbackPlant.id, default: 0] += 1
                }
            }
        }

        totalPoints -= totalCost
        let message = "Successfully pulled \(pulledBlueprints.count) plants!" + (numberOfPulls == 10 ? " (Last one guaranteed Rare or better!)" : "")
        return (true, pulledBlueprints, message)
    }

    private func getPlantByRarity(theme: PlantTheme, rarity: Rarity, themeSpecificBlueprints: [PlantBlueprint]) -> PlantBlueprint? {
        let availablePlants = themeSpecificBlueprints.filter { $0.rarity == rarity }
        if let chosen = availablePlants.randomElement() {
            return chosen
        }
        if rarity != .common, let chosen = themeSpecificBlueprints.filter({ $0.rarity == .common }).randomElement() { return chosen }
        return themeSpecificBlueprints.randomElement()
    }

    private func getGuaranteedRareOrBetterPlant(theme: PlantTheme, themeSpecificBlueprints: [PlantBlueprint]) -> PlantBlueprint? {
        let randomPercent = Double.random(in: 0..<100)
        var selectedRarity: Rarity
        if randomPercent < 60.0 { selectedRarity = .rare }
        else if randomPercent < 90.0 { selectedRarity = .epic }
        else { selectedRarity = .legendary }
        return getPlantByRarity(theme: theme, rarity: selectedRarity, themeSpecificBlueprints: themeSpecificBlueprints)
    }
    
    func convertToFertilizer(blueprintID: String, quantityToConvert: Int) -> (success: Bool, fertilizerGained: Int, message: String) {
        guard quantityToConvert > 0 else {
            return (false, 0, "Quantity to convert must be greater than zero.")
        }
        guard let plantName = PlantLibrary.blueprint(withId: blueprintID)?.name else {
             return (false, 0, "Unknown plant type.")
        }
        guard let currentQuantity = unplacedPlantsInventory[blueprintID], currentQuantity >= quantityToConvert else {
            return (false, 0, "Not enough \(plantName) to convert. You have \(unplacedPlantsInventory[blueprintID] ?? 0).")
        }
        guard quantityToConvert % 10 == 0 else {
            return (false, 0, "You can only convert plants in multiples of 10 for fertilizer.")
        }

        let fertilizerProduced = quantityToConvert / 10
        
        unplacedPlantsInventory[blueprintID]? -= quantityToConvert
        if unplacedPlantsInventory[blueprintID] ?? 0 <= 0 {
            unplacedPlantsInventory.removeValue(forKey: blueprintID)
        }
        self.fertilizerCount += fertilizerProduced
        return (true, fertilizerProduced, "Successfully converted \(quantityToConvert) \(plantName)(s) into \(fertilizerProduced) fertilizer.")
    }

    func updateGardenValue() {
        var calculatedTotalGardenValue: Double = 100.0
        for plant in placedPlants {
             // getCurrentDynamicValue already checks if plant isFullyGrown
            calculatedTotalGardenValue += plant.getCurrentDynamicValue()
        }
        self.gardenValue = calculatedTotalGardenValue
    }

    func sellPlant(plantId: UUID) -> Bool {
        if let plantIndex = placedPlants.firstIndex(where: { $0.id == plantId }) {
            let plantToSell = placedPlants[plantIndex]
            
            guard plantToSell.isFullyGrown else {
                return false
            }

            let sellPrice = plantToSell.baseValue * 1.5 // Sell price is fixed at 1.5x baseValue
            
            self.totalPoints += sellPrice
            placedPlants.remove(at: plantIndex)
            updateGardenValue()
            return true
        }
        return false
    }

    func useFertilizer(onPlantID plantId: UUID) -> (success: Bool, message: String) {
        guard fertilizerCount > 0 else {
            return (false, "No fertilizer left!")
        }
        
        guard let plantIndex = placedPlants.firstIndex(where: { $0.id == plantId }) else {
            return (false, "Plant not found.")
        }
        
        var plantToFertilize = placedPlants[plantIndex]
        
        guard !plantToFertilize.isFullyGrown else {
            return (false, "\(plantToFertilize.name) is already fully grown!")
        }
        
        plantToFertilize.makeFullyGrown()
        fertilizerCount -= 1
        placedPlants[plantIndex] = plantToFertilize
        
        updateGardenValue()
        
        return (true, "\(plantToFertilize.name) is now fully grown!")
    }
}

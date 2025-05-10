//
//  PlantLibrary.swift
//  YourDay
//
//  Created by Rachit Verma on 5/9/25.
//
//

import Foundation

/// Defines the static properties of a type of plant available in the game.
struct PlantBlueprint: Identifiable, Hashable {
    let id: String // Unique identifier for this plant species, e.g., "sunflower_common_summer"
    let name: String // Display name, e.g., "Sunflower"
    let description: String // A short description for the plant
    let rarity: Rarity
    let theme: PlantTheme
    let initialDaysToGrow: Int
    let baseValue: Double // The value of the plant when fully grown (before seasonal/other multipliers)
    let assetName: String // Placeholder for image asset name, e.g., "sunflower_grown.png"
    let iconName: String // Placeholder for a smaller icon asset name, e.g., "sunflower_icon.png"

    // Example: How many points this plant might cost in a shop or its "seed" value
    let purchaseCost: Double? // Optional, if plants can be bought

    // You could add more static properties here, like:
    // - Special abilities when grown
    // - Specific nutrient needs, etc.
}

/// A library to hold all defined plant blueprints in the game.
struct PlantLibrary {
    static let allPlantBlueprints: [PlantBlueprint] = [
        // --- Common Plants ---
        PlantBlueprint(
            id: "sunflower_c_su", name: "Sunflower",
            description: "A cheerful and common flower that loves the sun.",
            rarity: .common, theme: .summer,
            initialDaysToGrow: 1, baseValue: 50, // Common: 1 day, 50 value
            assetName: "placeholder_sunflower_grown.png", iconName: "icon_sunflower.png",
            purchaseCost: 20
        ),
        PlantBlueprint(
            id: "tulip_c_sp", name: "Tulip",
            description: "A classic spring bulb, vibrant and colorful.",
            rarity: .common, theme: .spring,
            initialDaysToGrow: 1, baseValue: 50,
            assetName: "placeholder_tulip_grown.png", iconName: "icon_tulip.png",
            purchaseCost: 20
        ),
        PlantBlueprint(
            id: "marigold_c_fa", name: "Marigold",
            description: "A hardy flower known for its bright orange and yellow blooms in autumn.",
            rarity: .common, theme: .fall,
            initialDaysToGrow: 1, baseValue: 50,
            assetName: "placeholder_marigold_grown.png", iconName: "icon_marigold.png",
            purchaseCost: 25
        ),
        PlantBlueprint(
            id: "pansy_c_wi", name: "Pansy",
            description: "A resilient flower that can add color even in cooler winter months.",
            rarity: .common, theme: .winter,
            initialDaysToGrow: 1, baseValue: 50,
            assetName: "placeholder_pansy_grown.png", iconName: "icon_pansy.png",
            purchaseCost: 25
        ),

        // --- Uncommon Plants ---
        PlantBlueprint(
            id: "lavender_uc_su", name: "Lavender",
            description: "Known for its soothing scent and beautiful purple spikes.",
            rarity: .uncommon, theme: .summer,
            initialDaysToGrow: 2, baseValue: 150, // Example for Uncommon
            assetName: "placeholder_lavender_grown.png", iconName: "icon_lavender.png",
            purchaseCost: 70
        ),
        PlantBlueprint(
            id: "daffodil_uc_sp", name: "Daffodil",
            description: "A joyful herald of spring with its trumpet-shaped corona.",
            rarity: .uncommon, theme: .spring,
            initialDaysToGrow: 2, baseValue: 150,
            assetName: "placeholder_daffodil_grown.png", iconName: "icon_daffodil.png",
            purchaseCost: 70
        ),

        // --- Rare Plants ---
        PlantBlueprint(
            id: "rose_r_sp", name: "Mystic Rose",
            description: "A beautiful rose with an enchanting aura. Blooms best in spring.",
            rarity: .rare, theme: .spring,
            initialDaysToGrow: 2, baseValue: 250, // Rare: 2 days, 250 value
            assetName: "placeholder_rose_grown.png", iconName: "icon_rose.png",
            purchaseCost: 120
        ),
        PlantBlueprint(
            id: "orchid_r_su", name: "Sun Orchid",
            description: "An exotic orchid that thrives in summer's warmth.",
            rarity: .rare, theme: .summer,
            initialDaysToGrow: 2, baseValue: 250,
            assetName: "placeholder_orchid_grown.png", iconName: "icon_orchid.png",
            purchaseCost: 130
        ),

        // --- Epic Plants ---
        PlantBlueprint(
            id: "moonflower_e_fa", name: "Moonflower",
            description: "A magical flower that blooms only under the autumn moonlight.",
            rarity: .epic, theme: .fall,
            initialDaysToGrow: 3, baseValue: 500, // Epic: 3 days, 500 value
            assetName: "placeholder_moonflower_grown.png", iconName: "icon_moonflower.png",
            purchaseCost: 250
        ),
        PlantBlueprint(
            id: "crystalbloom_e_wi", name: "Crystal Bloom",
            description: "A rare plant whose petals shimmer like ice crystals in winter.",
            rarity: .epic, theme: .winter,
            initialDaysToGrow: 3, baseValue: 500,
            assetName: "placeholder_crystalbloom_grown.png", iconName: "icon_crystalbloom.png",
            purchaseCost: 270
        ),
        
        // --- Legendary Plants ---
        PlantBlueprint(
            id: "starpetal_l_sp", name: "Starpetal",
            description: "A legendary flower said to capture the light of stars. A spring marvel.",
            rarity: .legendary, theme: .spring,
            initialDaysToGrow: 5, baseValue: 1000, // Legendary: 5 days, 1000 value
            assetName: "placeholder_starpetal_grown.png", iconName: "icon_starpetal.png",
            purchaseCost: 500
        ),
        PlantBlueprint(
            id: "phoenixbloom_l_su", name: "Phoenix Bloom",
            description: "Reborn from ashes, this legendary summer plant symbolizes eternal life.",
            rarity: .legendary, theme: .summer,
            initialDaysToGrow: 5, baseValue: 1000,
            assetName: "placeholder_phoenixbloom_grown.png", iconName: "icon_phoenixbloom.png",
            purchaseCost: 550
        )
        // Add more plant definitions here as you design them
    ]

    /// Helper function to get a plant blueprint by its unique ID.
    static func blueprint(withId id: String) -> PlantBlueprint? {
        return allPlantBlueprints.first(where: { $0.id == id })
    }

    /// Helper function to get all plant blueprints of a specific rarity.
    static func blueprints(withRarity rarity: Rarity) -> [PlantBlueprint] {
        return allPlantBlueprints.filter { $0.rarity == rarity }
    }
    
    
}

